#!/bin/bash

# Create a single parent backup directory with timestamp
PARENT_DIR="./k8s-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$PARENT_DIR"

# Get all namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for NAMESPACE in $NAMESPACES; do
  NS_DIR="$PARENT_DIR/$NAMESPACE"
  mkdir -p "$NS_DIR/secrets"
  mkdir -p "$NS_DIR/configmaps"
  echo "Backing up secrets in namespace: $NAMESPACE"
  SECRETS=$(kubectl get secrets -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
  for SECRET in $SECRETS; do
    echo "  Saving secret $SECRET to $NS_DIR/secrets/$SECRET.yaml"
    kubectl get secret $SECRET -n $NAMESPACE -o yaml > "$NS_DIR/secrets/$SECRET.yaml"
  done
  echo "Backing up configmaps in namespace: $NAMESPACE"
  CONFIGMAPS=$(kubectl get configmaps -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
  for CONFIGMAP in $CONFIGMAPS; do
    echo "  Saving configmap $CONFIGMAP to $NS_DIR/configmaps/$CONFIGMAP.yaml"
    kubectl get configmap $CONFIGMAP -n $NAMESPACE -o yaml > "$NS_DIR/configmaps/$CONFIGMAP.yaml"
  done
  echo "All secrets and configmaps in namespace $NAMESPACE have been saved to $NS_DIR"
done

echo "All namespaces have been backed up to $PARENT_DIR"