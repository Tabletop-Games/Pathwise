#!/usr/bin/env bash
# Deploys the Pathwise backend to Cloud Run. Creates billable resources only
# when you run it. Usage:
#   PROJECT_ID=... REGION=... ENVIRONMENT=production|development \
#   ENV_FILE=/secure/pathwise-backend.production.yaml ./deploy/deploy.sh
set -euo pipefail
: "${PROJECT_ID:?set PROJECT_ID}"
: "${REGION:?set REGION, for example us-central1}"
: "${ENVIRONMENT:?set ENVIRONMENT to production or development}"
: "${ENV_FILE:?set ENV_FILE to a filled copy of deploy/env.<environment>.example.yaml}"
case "$ENVIRONMENT" in production|development) ;; *) echo "ENVIRONMENT must be production or development" >&2; exit 1 ;; esac

SERVICE="pathwise-api-${ENVIRONMENT}"
RUNTIME_SA="pathwise-api@${PROJECT_ID}.iam.gserviceaccount.com"
cd "$(dirname "$0")/.."

gcloud run deploy "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION" --source . \
  --service-account "$RUNTIME_SA" \
  --allow-unauthenticated \
  --env-vars-file "$ENV_FILE" \
  --set-secrets "PATHWISE_SESSION_KEYS=pathwise-session-keys:latest,PATHWISE_PGS_WEB_CLIENT_SECRET=pathwise-pgs-web-client-secret:latest" \
  --cpu 1 --memory 512Mi --concurrency 40 \
  --min-instances 0 --max-instances "${MAX_INSTANCES:-10}" \
  --timeout 30s \
  --cpu-boost \
  --execution-environment gen2 \
  --ingress all

URL="$(gcloud run services describe "$SERVICE" --project "$PROJECT_ID" --region "$REGION" --format 'value(status.url)')"
echo "Deployed $SERVICE at $URL"
echo "Verify: curl -fsS $URL/healthz"
