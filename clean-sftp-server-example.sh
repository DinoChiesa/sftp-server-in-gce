#!/bin/bash

# Copyright 2023-2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

EXAMPLE_NAME="sftp-server-example"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
VM_SA_PREFIX="${EXAMPLE_NAME}-"
BUCKET_PREFIX="${EXAMPLE_NAME}-"
VM_INSTANCE_PREFIX="sftp-example-instance-"
FWALL_PREFIX="sftp-example-allow-"

remove_gce_vm() {
    printf "Checking for VM instances like (%s*)\n" "${VM_INSTANCE_PREFIX}"
    # shellcheck disable=SC2207
    ARR=($(gcloud compute instances list --project="$GCP_PROJECT" --quiet --format='value[](name)' | grep "$VM_INSTANCE_PREFIX"))
    if [[ ${#ARR[@]} -gt 0 ]]; then
        for instance in "${ARR[@]}"; do
            printf "Stopping and removing instance %s...\n" "${instance}"
            gcloud compute instances stop "${instance}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}"
            gcloud compute instances delete "${instance}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" --quiet
        done
    else
        printf "Found none.\n"
    fi
}

remove_sa() {
    printf "Checking for service accounts like (%s*)\n" "${VM_SA_PREFIX}"
    # shellcheck disable=SC2207
    ARR=($(gcloud iam service-accounts list --project="$GCP_PROJECT" --quiet --format='value[](email)' | grep "$VM_SA_PREFIX"))
    if [[ ${#ARR[@]} -gt 0 ]]; then
        for sa in "${ARR[@]}"; do
            printf "Deleting service account %s...\n" "${sa}"
            gcloud --quiet iam service-accounts delete "${sa}" --project="$GCP_PROJECT"
        done
    else
        printf "Found none.\n"
    fi
}

remove_gcs_bucket() {
    printf "Checking for GCS buckets like (%s*)\n" "${BUCKET_PREFIX}"
    # shellcheck disable=SC2207
    ARR=($(gcloud storage buckets list --project="$GCP_PROJECT" --quiet --format='value[](storage_url)' | grep "$BUCKET_PREFIX"))
    if [[ ${#ARR[@]} -gt 0 ]]; then
        for bucket in "${ARR[@]}"; do
            # rm -r removes the objects AND the bucket itself
            printf "clearing and removing bucket %s...\n" "${bucket}"
            gcloud storage rm --recursive "${bucket}" --project="$GCP_PROJECT"
            # this is not necessary
            # printf "removing bucket %s...\n" "${bucket}"
            # gcloud storage buckets delete "${bucket}" --project="$GCP_PROJECT"
        done
    else
        printf "Found none.\n"
    fi
}

remove_firewall_rules() {
    printf "Checking for GCM Firewall rules (%s*)\n" "${FWALL_PREFIX}"
    # shellcheck disable=SC2207
    ARR=($(gcloud compute firewall-rules list --project="$GCP_PROJECT" --quiet --format='value[](name)' | grep "$FWALL_PREFIX"))
    if [[ ${#ARR[@]} -gt 0 ]]; then
        for rule in "${ARR[@]}"; do
            printf "removing firewall rule %s...\n" "${rule}"
            gcloud compute firewall-rules delete "${rule}" --project="$GCP_PROJECT" --quiet
        done
    else
        printf "Found none.\n"
    fi
}

MISSING_ENV_VARS=()
[[ -z "$GCP_PROJECT" ]] && MISSING_ENV_VARS+=('GCP_PROJECT')
[[ -z "$GCE_VM_ZONE" ]] && MISSING_ENV_VARS+=('GCE_VM_ZONE')
[[ -z "$GCS_REGION" ]] && MISSING_ENV_VARS+=('GCS_REGION')

[[ ${#MISSING_ENV_VARS[@]} -ne 0 ]] && {
    printf -v joined '%s,' "${MISSING_ENV_VARS[@]}"
    printf "You must set these environment variables: %s\n" "${joined%,}"
    exit 1
}

OUTFILE=$(mktemp /tmp/appint-samples.gcloud.out.XXXXXX)

printf "\nClean-up for the SFTP Server Example in GCE.\n\n"

remove_gce_vm
remove_sa
remove_gcs_bucket
remove_firewall_rules

printf "\nAll the GCE and GCS artifacts should have been removed.\n\n"
