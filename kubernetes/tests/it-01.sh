#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="https://app.s8-hetzner.online/api/handle"

TARGET_URL="$TARGET_URL" k6 run - <<'K6'
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    frontend_backend_api: {
      executor: 'constant-arrival-rate',
      rate: 2000,
      timeUnit: '1m',
      duration: '2m',
      preAllocatedVUs: 25,
      maxVUs: 100,
    },
  },
  discardResponseBodies: true,
  thresholds: {
    http_req_failed: ['rate<0.03'],
    http_req_duration: ['p(95)<2000'],
  },
};

const url = __ENV.TARGET_URL;
const payload = JSON.stringify({
  action: 'log',
  log: {
    name: 'loadtest',
    data: 'frontend-backend-loadtest',
  },
});

export default function () {
  const res = http.post(url, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, {
    'status is 202 accepted': (r) => r.status === 202,
  });
}
K6