#!/bin/bash
BRANCH_NAME="$1"
IMAGE_IDENTIFIER="$2"

echo "=== Deployment Script Started ==="
echo "Branch Name: $BRANCH_NAME"
echo "Image Identifier: $IMAGE_IDENTIFIER"
echo

# Determine the deployment environment based on BRANCH_NAME
if [[ "$BRANCH_NAME" == main* ]]; then
    DEPLOY_ENV="stage"
elif [[ "$BRANCH_NAME" == feature* ]]; then
    DEPLOY_ENV="dev"
else
    echo "Error: Unsupported branch name. Must start with 'main' or 'feature'."
    exit 1
fi

echo "Deployment Environment: $DEPLOY_ENV"
echo

# Retrieve the App Runner service ARN that matches the deployment environment
echo "Retrieving App Runner service ARN for environment: $DEPLOY_ENV in region: $AWS_REGION"
SERVICE_ARN=$(aws apprunner list-services \
    --region "$AWS_REGION" \
    --query "ServiceSummaryList[?contains(ServiceName, '${DEPLOY_ENV}')].ServiceArn" \
    --output text)

# Check if exactly one service was found
SERVICE_COUNT=$(echo "$SERVICE_ARN" | wc -w)

if [ "$SERVICE_COUNT" -eq 0 ]; then
    echo "No App Runner services found for environment: $DEPLOY_ENV in region: $AWS_REGION"
    exit 0
elif [ "$SERVICE_COUNT" -gt 1 ]; then
    echo "Error: Multiple App Runner services found for environment: $DEPLOY_ENV in region: $AWS_REGION. Please ensure only one service matches the deployment environment."
    echo "Found Services:"
    echo "$SERVICE_ARN"
    exit 1
fi

echo "Found Service ARN:"
echo "$SERVICE_ARN"
echo

# Update the App Runner service with the new image
echo "=== Updating Service: $SERVICE_ARN ==="

aws apprunner update-service \
    --service-arn "$SERVICE_ARN" \
    --source-configuration ImageRepository="{ImageIdentifier=${IMAGE_IDENTIFIER},ImageRepositoryType=ECR}" \
    --region "$AWS_REGION"

echo "Update initiated for service: $SERVICE_ARN"
echo

# Wait until the service update is no longer in progress
echo "Monitoring update status for service: $SERVICE_ARN"
while true; do
    STATUS=$(aws apprunner describe-service \
        --service-arn "$SERVICE_ARN" \
        --region "$AWS_REGION" \
        --query 'Service.Status' \
        --output text)
    echo "Current Status for $SERVICE_ARN: $STATUS"
    if [[ "$STATUS" != "OPERATION_IN_PROGRESS" ]]; then
        break
    fi
    sleep 10
done

echo "Update completed for service: $SERVICE_ARN with status: $STATUS"
echo

echo "=== Deployment Completed Successfully ==="
