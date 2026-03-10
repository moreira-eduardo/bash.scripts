#!/bin/bash

# Variables
SOURCE_AKV_NAME=""
SOURCE_RESOURCE_GROUP=""
TARGET_AKV_NAME=""
TARGET_RESOURCE_GROUP=""
SOURCE_SUBSCRIPTION_ID=""
TARGET_SUBSCRIPTION_ID=""

# Set the source subscription
az account set --subscription $SOURCE_SUBSCRIPTION_ID

# Copy Secrets
echo "Copying secrets from $SOURCE_AKV_NAME to $TARGET_AKV_NAME..."
SECRETS=$(az keyvault secret list --vault-name $SOURCE_AKV_NAME --query "[].id" -o tsv)
for SECRET_ID in $SECRETS; do
  SECRET_NAME=$(basename $SECRET_ID)
  SECRET_VALUE=$(az keyvault secret show --id $SECRET_ID --query "value" -o tsv)
  
  # Set the target subscription
  az account set --subscription $TARGET_SUBSCRIPTION_ID
  az keyvault secret set --vault-name $TARGET_AKV_NAME --name $SECRET_NAME --value "$SECRET_VALUE"
  
  # Set back to the source subscription
  az account set --subscription $SOURCE_SUBSCRIPTION_ID
done

# Copy Keys
echo "Copying keys from $SOURCE_AKV_NAME to $TARGET_AKV_NAME..."
KEYS=$(az keyvault key list --vault-name $SOURCE_AKV_NAME --query "[].kid" -o tsv)
for KEY_ID in $KEYS; do
  KEY_NAME=$(basename $KEY_ID)
  KEY_JSON=$(az keyvault key show --id $KEY_ID)
  KEY_OPS=$(echo $KEY_JSON | jq -r '.key_ops | join(",")')
  KEY_TYPE=$(echo $KEY_JSON | jq -r '.kty // empty')
  KEY_CURVE=$(echo $KEY_JSON | jq -r '.crv // empty')
  KEY_SIZE=$(echo $KEY_JSON | jq -r '.key_size // empty')
  
  if [ -z "$KEY_TYPE" ]; then
    echo "Skipping key $KEY_NAME: key type is null"
    continue
  fi
  
  # Set the target subscription
  az account set --subscription $TARGET_SUBSCRIPTION_ID
  az keyvault key create --vault-name $TARGET_AKV_NAME --name $KEY_NAME --ops $KEY_OPS --kty $KEY_TYPE --curve $KEY_CURVE --size $KEY_SIZE
  
  # Set back to the source subscription
  az account set --subscription $SOURCE_SUBSCRIPTION_ID
done

# Copy Certificates
echo "Copying certificates from $SOURCE_AKV_NAME to $TARGET_AKV_NAME..."
CERTIFICATES=$(az keyvault certificate list --vault-name $SOURCE_AKV_NAME --query "[].id" -o tsv)
for CERT_ID in $CERTIFICATES; do
  CERT_NAME=$(basename $CERT_ID)
  az keyvault certificate backup --vault-name $SOURCE_AKV_NAME --name $CERT_NAME --file /tmp/$CERT_NAME.cert
  
  # Set the target subscription
  az account set --subscription $TARGET_SUBSCRIPTION_ID
  az keyvault certificate restore --vault-name $TARGET_AKV_NAME --file /tmp/$CERT_NAME.cert
  rm /tmp/$CERT_NAME.cert
  
  # Set back to the source subscription
  az account set --subscription $SOURCE_SUBSCRIPTION_ID
done

echo "Copying completed successfully."