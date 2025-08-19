@echo off
set VERCEL_URL=dev-test-%RANDOM%
set VERCEL_ENV=production
set REDISHOST=localhost
set REDISPORT=6379
set DEBUG_CACHE_HANDLER=true

echo %VERCEL_URL%
cd ../../..
call pnpm build
cd test/integration/next-app-15-4-7
call pnpm i
call pnpm build
start "" pnpm start
