# nextjs-turbo-redis-cache

[![npm version](https://img.shields.io/npm/v/@trieb.work/nextjs-turbo-redis-cache.svg)](https://www.npmjs.com/package/@trieb.work/nextjs-turbo-redis-cache)
![Turbo redis cache image](https://github.com/user-attachments/assets/98e0dfd9-f38a-42ad-a355-9843740cc2d6)




The ultimate Redis caching solution for Next.js. Built for production-ready, large-scale projects, it delivers unparalleled performance and efficiency with features tailored for high-traffic applications. This package has been created after extensibly testing the @neshca package and finding several major issues with it.

Key Features:

- _Batch Tag Invalidation_: Groups and optimizes delete operations for minimal Redis stress.
- _Request Deduplication_: Prevents redundant Redis get calls, ensuring faster response times.
- _In-Memory Caching_: Includes local caching for Redis get operations to reduce latency further. Don't request redis for the same key multiple times.
- _Efficient Tag Management_: in-memory tags map for lightning-fast revalidate operations with minimal Redis overhead.
- _Intelligent Key-Space Notifications_: Automatic update of in-memory tags map for expired or evicted keys.

## Compatibility

This package is compatible with Next.js 15.0.3 and above while using App Router. It is not compatible with Next.js 14.x. or 15-canary or if you are using Pages Router.
Redis need to have Redis Version 2.8.0 or higher and have to be configured with `notify-keyspace-events` to be able to use the key-space notifications feature.

Tested versions are:

- 15.0.3
- 15.2.4
- 15.3.2
  Currently PPR, 'use cache', cacheLife and cacheTag are not tested. Use these operations with caution and your own risk.

## Available Options (needs Option B of getting started)

| Option                 | Description                                                                                                       | Default Value                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | --- | ----------------- |
| database               | Redis database number to use. Uses DB 0 for production, DB 1 otherwise                                            | `process.env.VERCEL_ENV === 'production' ? 0 : 1`     |
| keyPrefix              | Prefix added to all Redis keys                                                                                    | `process.env.VERCEL_URL                               |     | 'UNDEFINED*URL*'` |
| sharedTagsKey          | Key used to store shared tags hash map in Redis                                                                   | `'__sharedTags__'`                                    |
| timeoutMs              | Timeout in milliseconds for Redis operations                                                                      | `5000`                                                |
| revalidateTagQuerySize | Number of entries to query in one batch during full sync of shared tags hash map                                  | `250`                                                 |
| avgResyncIntervalMs    | Average interval in milliseconds between tag map full re-syncs                                                    | `3600000` (1 hour)                                    |
| redisGetDeduplication  | Enable deduplication of Redis get requests via internal in-memory cache.                                          | `true`                                                |
| inMemoryCachingTime    | Time in milliseconds to cache Redis get results in memory. Set this to 0 to disable in-memory caching completely. | `10000`                                               |
| defaultStaleAge        | Default stale age in seconds for cached items                                                                     | `1209600` (14 days)                                   |
| estimateExpireAge      | Function to calculate expire age (redis TTL value) from stale age                                                 | Production: `staleAge * 2`<br>Other: `staleAge * 1.2` |

## Getting started

### Enable redis key-space notifications for Expire and Evict events

```bash
redis-cli -h localhost config set notify-keyspace-events Exe
```

### Install package

```bash
pnpm install @trieb.work/nextjs-turbo-redis-cache
```

### Setup environment variables in your project/deployment

REDISHOST and REDISPORT environment variables are required.
VERCEL_URL, VERCEL_ENV are optional. VERCEL_URL is used to create a key prefix for the redis keys. VERCEL_ENV is used to determine the database to use. Only VERCEL_ENV=production will show up in DB 0 (redis default db). All other values of VERCEL_ENV will use DB 1, use `redis-cli -n 1` to connect to different DB 1. This is another protection feature to avoid that different environments (e.g. staging and production) will overwrite each other.
Furthermore there exists the DEBUG_CACHE_HANDLER environment variable to enable debug logging of the caching handler once it is set to true.

### Option A: minimum implementation with default options

extend `next.config.js` with:

```
const nextConfig = {
  ...
  cacheHandler: require.resolve("@trieb.work/nextjs-turbo-redis-cache")
  ...
}
```

### Option B: create a wrapper file to change options

create new file `customized-cache-handler.js` in your project root and add the following code:

```
const { RedisStringsHandler } = require('@trieb.work/nextjs-turbo-redis-cache');

let cachedHandler;

module.exports = class CustomizedCacheHandler {
  constructor() {
    if (!cachedHandler) {
      cachedHandler = new RedisStringsHandler({
        database: 0,
        keyPrefix: 'test',
        timeoutMs: 2_000,
        revalidateTagQuerySize: 500,
        sharedTagsKey: '__sharedTags__',
        avgResyncIntervalMs: 10_000 * 60,
        redisGetDeduplication: false,
        inMemoryCachingTime: 0,
        defaultStaleAge: 1209600,
        estimateExpireAge: (staleAge) => staleAge * 2,
      });
    }
  }
  get(...args) {
    return cachedHandler.get(...args);
  }
  set(...args) {
    return cachedHandler.set(...args);
  }
  revalidateTag(...args) {
    return cachedHandler.revalidateTag(...args);
  }
  resetRequestCache(...args) {
    return cachedHandler.resetRequestCache(...args);
  }
}
```

extend `next.config.js` with:

```
const nextConfig = {
  ...
  cacheHandler: require.resolve("./customized-cache-handler")
  ...
}
```

A working example of above can be found in the `test/integration/next-app-customized` folder.

## Consistency of Redis and this caching implementation

To understand consistency levels of this caching implementation we first have to understand the consistency of redis itself:
Redis executes commands in a single-threaded manner. This ensures that all operations are processed sequentially, so clients always see a consistent view of the data.
But depending on the setup of redis this can change:

- Strong consistency: only for single node setup
- Eventual consistency: In a master-replica setup (strong consistency only while there is no failover)
- Eventual consistency: In Redis Cluster mode

Consistency levels of Caching Handler:
If Redis is used in a single node setup and Request Deduplication is turned off, only then the caching handler will have strong consistency.

If using Request Deduplication, the strong consistency is not guaranteed anymore. The following sequence can happen with request deduplication:
Instance 1: call set A 1
Instance 1: served set A 1
Instance 2: call get A
Instance 1: call delete A
Instance 2: call get A
Instance 2: served get A -> 1
Instance 2: served get A -> 1 (served 1 but should already be deleted)
Instance 1: served delete A

The time window for this eventual consistency to occur is typically around the length of a single redis command. Depending on your load ranging from 5ms to max 100ms.
If using local in-memory caching (Enabled by RedisStringsHandler option inMemoryCachingTime), the window for this eventual consistency to occur can be even higher because additionally also synchronization messages have to get delivered. Depending on your load typically ranging around 50ms to max of 120ms.

Since all caching calls in one api/page/server action request is always served by the same instance this problem will not occur inside a single request but rather in a combination of multiple parallel requests. The probability that this will occur for a single user during a request sequence is very low, since typically a single user will not make the follow up request during this small time window of typically 50ms. To further mitigate the Problem and increase performance (increase local in-memory cache hit ratio) make sure that your load balancer will always serve one user to the same instance (sticky sessions).

By accepting and tolerating this eventual consistency, the performance of the caching handler is significantly increased.

## Development

1. Run `pnpm install` to install the dependencies
1. Run `pnpm build` to build the project
1. Run `pnpm lint` to lint the project
1. Run `pnpm format` to format the project
1. Run `pnpm run-dev-server` to test and develop the caching handler using the nextjs integration test project
1. If you make changes to the cache handler, you need to stop `pnpm run-dev-server` and run it again.

## Testing

To run all tests you can use the following command:

```bash
pnpm test
```

### Unit tests

To run unit tests you can use the following command:

```bash
pnpm test:unit
```

### Integration tests

To run integration tests you can use the following command:

```bash
pnpm test:integration
```

The integration tests will start a Next.js server and test the caching handler. You can modify testing behavior by setting the following environment variables:

- SKIP_BUILD: If set to true, the integration tests will not build the Next.js app. Therefore the nextjs app needs to be built before running the tests. Or you execute the test once without skip build and the re-execute `pnpm test:integration` with skip build set to true.
- SKIP_OPTIONAL_LONG_RUNNER_TESTS: If set to true, the integration tests will not run the optional long runner tests.
- DEBUG_INTEGRATION: If set to true, the integration tests will print debug information of the test itself to the console.

Integration tests may have dependencies between test cases, so individual test failures should be evaluated in the context of the full test suite rather than in isolation.

## Some words on nextjs caching internals

Nextjs will use different caching objects for different pages and api routes. Currently supported are kind: APP_ROUTE and APP_PAGE.

app/<segment>/route.ts files will request using the APP_ROUTE kind.
app/<segment>/page.tsx files will request using the APP_PAGE kind.
/favicon.ico file will request using the APP_ROUTE kind.

Fetch requests (inside app route or page) will request using the FETCH kind.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Sponsor

This project is created and maintained by the Next.js & Payload CMS agency [trieb.work](https://trieb.work)
