#!/bin/bash

# Print the header line first
echo -e "NAMESPACE\tNAME\tISSUED_DATE\tEXPIRATION_DATE\tEXPIRE_YEAR"

# Then print out the data lines as before
kubectl get secrets --all-namespaces -o json | \
jq -r '
  .items[]
  | select(.type=="kubernetes.io/tls")
  | [.metadata.namespace, .metadata.name, .data["tls.crt"]]
  | @tsv
' | while IFS=$'\t' read -r NAMESPACE NAME CRT_BASE64; do
  if [ -n "$CRT_BASE64" ]; then
    DECODED=$(echo "$CRT_BASE64" | base64 -d 2>/dev/null)
    NOT_BEFORE=$(echo "$DECODED" | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)
    NOT_AFTER=$(echo "$DECODED" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    EXPIRE_YEAR=$(echo "$NOT_AFTER" | awk '{print $4}')
    echo -e "$NAMESPACE\t$NAME\t$NOT_BEFORE\t$NOT_AFTER\t$EXPIRE_YEAR"
  fi
done | column -t -s $'\t'