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

EXAMPLE_NAME="${EXAMPLE_PREFIX}-sftpgo"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
# shellcheck disable=SC2002
rand_string=$(cat /dev/urandom | LC_CTYPE=C tr -cd '[:alnum:]' | head -c 6 | tr '[:upper:]' '[:lower:]')
VM_SA="${EXAMPLE_NAME}-${rand_string}"
VM_TAG="${EXAMPLE_NAME}"
FULL_SA_EMAIL="${VM_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
BUCKET_NAME="${EXAMPLE_NAME}-bucket"
PUBSUB_TOPIC="${EXAMPLE_NAME}-topic"
FWALL_PREFIX="${EXAMPLE_NAME}-allow-"
VM_INSTANCE_NAME="${EXAMPLE_NAME}-instance-${rand_string}-${TIMESTAMP}"
SA_REQUIRED_ROLES=("roles/storage.objectViewer" "roles/storage.objectCreator" "roles/storage.objectUser")
# not needed: roles/storage.objectAdmin
SFTP_USER="testuser"

check_and_maybe_create_gcs_bucket() {
  printf "Checking GCS bucket (%s)...\n" "gs://${BUCKET_NAME}"
  if gcloud storage buckets describe "gs://${BUCKET_NAME}" --format="json(name)" --project="$GCP_PROJECT" --quiet >"$OUTFILE" 2>&1; then
    printf "That bucket already exists.\n"
  else
    printf "Creating the bucket...\n"
    gcloud storage buckets create "gs://${BUCKET_NAME}" --default-storage-class=standard --location="${GCS_REGION}" --project="$GCP_PROJECT" --quiet >"$OUTFILE" 2>&1
    # The following sets up a notification to pubsub on object finalization.
    # If the topic doesn't exist in the GCP project, this command creates it.
    gcloud storage buckets notifications create "gs://${BUCKET_NAME}" --topic="${PUBSUB_TOPIC}" --project="$GCP_PROJECT" --quiet --event-types="OBJECT_FINALIZE" >"$OUTFILE" 2>&1
  fi
}

check_and_maybe_create_sa() {
  local ROLE
  printf "Checking Service account (%s)...\n" "${VM_SA}"
  if gcloud iam service-accounts describe "${FULL_SA_EMAIL}" --project="$GCP_PROJECT" --quiet >"$OUTFILE" 2>&1; then
    printf "That service account already exists.\n"
    printf "Checking for required roles....\n"

    # I could not get the --filter argument to work here. :<
    # shellcheck disable=SC2076
    ARR=($(gcloud storage buckets get-iam-policy "gs://${BUCKET_NAME}" --project="${GCP_PROJECT}" \
      --flatten="bindings[].members" |
      grep -v deleted |
      grep -A 1 members |
      grep -A 1 "$FULL_SA_EMAIL" |
      grep role | sed -e 's/role: //'))

    for j in "${!SA_REQUIRED_ROLES[@]}"; do
      ROLE=${SA_REQUIRED_ROLES[j]}
      printf "check the role %s...\n" "$ROLE"
      if ! [[ ${ARR[*]} =~ "${ROLE}" ]]; then
        printf "Adding role %s...\n" "${ROLE}"
        gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --project="${GCP_PROJECT}" \
          --member="serviceAccount:${FULL_SA_EMAIL}" --role="${ROLE}" --quiet >/dev/null 2>&1
      else
        printf "That role is already set...\n"
      fi
    done

  else
    echo "$VM_SA" >./.vm_sa_name
    gcloud iam service-accounts create "$VM_SA" --project="${GCP_PROJECT}" --quiet

    printf "There can be errors if all these changes happen too quickly, so we need to sleep a bit...\n"
    sleep 12

    printf "Granting access for that service account to the GCS bucket...\n"
    for j in "${!SA_REQUIRED_ROLES[@]}"; do
      ROLE=${SA_REQUIRED_ROLES[j]}
      printf "Adding role %s...\n" "${ROLE}"
      gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --project="${GCP_PROJECT}" \
        --member="serviceAccount:${FULL_SA_EMAIL}" --role="${ROLE}" --quiet >/dev/null 2>&1
    done
  fi
}

create_vm_instance() {
  echo "$VM_INSTANCE_NAME" >./.vm_instance_name

  #local SUBNET="subnet1"
  # inquire the network
  #local REGION=${GCE_VM_ZONE::-2}
  local REGION="${GCE_VM_ZONE%??}"

  local SUBNET=$(gcloud compute networks subnets list --filter="region:(  ${REGION} ) stack_type:(IPV4_ONLY)" --project="$GCP_PROJECT" --format="value[](name)" | head -1)

  local scopes=("https://www.googleapis.com/auth/devstorage.read_write"
    "https://www.googleapis.com/auth/logging.write"
    "https://www.googleapis.com/auth/monitoring.write"
    "https://www.googleapis.com/auth/service.management.readonly"
    "https://www.googleapis.com/auth/servicecontrol"
    "https://www.googleapis.com/auth/trace.append")

  local scopestring=$(printf ",%s" "${scopes[@]}")
  scopestring="${scopestring:1}"

  printf "Creating VM instance (%s) using subnet (%s)...\n" "${VM_INSTANCE_NAME}" "${SUBNET}"

  gcloud compute instances create "${VM_INSTANCE_NAME}" \
    --project="${GCP_PROJECT}" --zone="${GCE_VM_ZONE}" --machine-type=e2-small \
    --network-interface="stack-type=IPV4_ONLY,subnet=${SUBNET}" \
    --metadata=enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --service-account="${FULL_SA_EMAIL}" \
    --scopes="${scopestring}" \
    --tags="${VM_TAG}" \
    --create-disk=auto-delete=yes,boot=yes,device-name="${VM_INSTANCE_NAME}",image=projects/debian-cloud/global/images/debian-12-bookworm-v20240910,mode=rw,size=10,type=pd-balanced \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

  printf "Starting VM instance (%s)...\n" "${VM_INSTANCE_NAME}"
  gcloud compute instances start "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}"
}

create_firewall_rules() {
  local RULENAME="${FWALL_PREFIX}ingress"
  # inquire the default network
  local NETWORK_TO_USE=$(gcloud compute networks list --project=$GCP_PROJECT --format="value[](name)" | head -1)
  printf "Checking firewall ingress rule (%s)...\n" "${RULENAME}"
  if gcloud compute firewall-rules describe "${RULENAME}" --project="$GCP_PROJECT" --quiet >"$OUTFILE" 2>&1; then
    printf "That rule already exists.\n"
  else
    printf "Creating firewall ingress rule (%s)...\n" "${VM_INSTANCE_NAME}"
    gcloud compute firewall-rules create "${RULENAME}" --project="${GCP_PROJECT}" \
      --direction=INGRESS --priority=1000 \
      --network="${NETWORK_TO_USE}" \
      --action=ALLOW \
      --rules=tcp:22,tcp:2022,tcp:8080,tcp:60000-65535 \
      --source-ranges=0.0.0.0/0 \
      --target-tags="${VM_TAG}"
  fi

  RULENAME="${FWALL_PREFIX}egress"
  printf "Checking firewall egress rule (%s)...\n" "${RULENAME}"
  if gcloud compute firewall-rules describe "${RULENAME}" --project="$GCP_PROJECT" --quiet >"$OUTFILE" 2>&1; then
    printf "That rule already exists.\n"
  else
    printf "Creating firewall egress rule (%s)...\n" "${VM_INSTANCE_NAME}"
    gcloud compute firewall-rules create "${RULENAME}" --project="${GCP_PROJECT}" \
      --direction=EGRESS --priority=1000 \
      --network="${NETWORK_TO_USE}" \
      --action=ALLOW \
      --rules=tcp:22,tcp:60000-65535 \
      --source-ranges=0.0.0.0/0 \
      --target-tags="${VM_TAG}"
  fi
}

apt_update() {
  printf "apt update...\n"
  gcloud compute ssh "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" \
    --command="bash -s" <<EOF
sudo apt update
sudo apt-get clean all
EOF
}

install_sftpgo() {
  printf "Installing up stfpgo...\n"
  # must preface $ with backslash to prevent interpretation by THIS shell
  gcloud compute ssh "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" \
    --command="bash -s" <<EOF
[[ -f /usr/share/keyrings/sftpgo-archive-keyring.gpg ]] && sudo rm -f /usr/share/keyrings/sftpgo-archive-keyring.gpg
curl -sS https://ftp.osuosl.org/pub/sftpgo/apt/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/sftpgo-archive-keyring.gpg
RELEASE_CODENAME=\$(lsb_release -c -s)
echo "deb https://ftp.osuosl.org/pub/sftpgo/apt \${RELEASE_CODENAME} main" | sudo tee /etc/apt/sources.list.d/sftpgo.list
cat /usr/share/keyrings/sftpgo-archive-keyring.gpg | sudo apt-key add -
sudo apt-get update
sudo apt install -y sftpgo
sudo systemctl stop sftpgo
EOF

  printf "Setting up configuration for stfpgo...\n"
  gcloud compute scp ./config/sftpgo-initial-config.json "${VM_INSTANCE_NAME}":/tmp/sftpgo-initial-config.json --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}"
  gcloud compute scp ./config/sftpgo-initial-users.json "${VM_INSTANCE_NAME}":/tmp/sftpgo-initial-users.json --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}"

  gcloud compute ssh "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" \
    --command="bash -s" <<EOF
sudo cp /tmp/sftpgo-initial-config.json /etc/sftpgo/sftpgo.json
sudo chmod 644 /etc/sftpgo/sftpgo.json
sudo cp /tmp/sftpgo-initial-users.json /etc/sftpgo/users-store.json
sudo chmod 644 /etc/sftpgo/users-store.json
sudo mkdir -p /srv/sftpgo/data/${SFTP_USER}
sudo chown sftpgo:sftpgo /srv/sftpgo/data/${SFTP_USER}
sudo chmod 755 /srv/sftpgo/data/${SFTP_USER}
sudo mkdir /srv/sftpgo/data/${SFTP_USER}/gcs
sudo chown sftpgo:sftpgo /srv/sftpgo/data/${SFTP_USER}/gcs
sudo chmod 755 /srv/sftpgo/data/${SFTP_USER}/gcs
sudo systemctl start sftpgo
EOF

}

install_gcsfuse() {
  printf "Setting up gcsfuse...\n"
  gcloud compute ssh "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" \
    --command="bash -s" <<EOF
RELEASE_CODENAME=\$(lsb_release -c -s)
echo "deb https://packages.cloud.google.com/apt gcsfuse-\${RELEASE_CODENAME} main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update
sudo apt install -y fuse gcsfuse
EOF

  printf "mounting gcs via gcsfuse...\n"
  gcloud compute ssh "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" \
    --command "sudo gcsfuse -o allow_other  --file-mode=555 --dir-mode=777  ${BUCKET_NAME} /srv/sftpgo/data/${SFTP_USER}/gcs"
}

get_external_ip() {
  EXTERNAL_IP=$(gcloud compute instances describe "${VM_INSTANCE_NAME}" --project="$GCP_PROJECT" --zone="${GCE_VM_ZONE}" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
}

MISSING_ENV_VARS=()
[[ -z "$GCP_PROJECT" ]] && MISSING_ENV_VARS+=('GCP_PROJECT')
[[ -z "$GCE_VM_ZONE" ]] && MISSING_ENV_VARS+=('GCE_VM_ZONE')
[[ -z "$GCS_REGION" ]] && MISSING_ENV_VARS+=('GCS_REGION')
[[ -z "$EXAMPLE_PREFIX" ]] && MISSING_ENV_VARS+=('EXAMPLE_PREFIX')

[[ ${#MISSING_ENV_VARS[@]} -ne 0 ]] && {
  printf -v joined '%s,' "${MISSING_ENV_VARS[@]}"
  printf "You must set these environment variables: %s\n" "${joined%,}"
  exit 1
}

OUTFILE=$(mktemp /tmp/appint-samples.gcloud.out.XXXXXX)

printf "\n\nSetup for an SFTPGo Server Example in GCE.\n\n"
check_and_maybe_create_gcs_bucket
check_and_maybe_create_sa
create_vm_instance
create_firewall_rules
printf "Waiting a bit until we can SSH into the machine.....\n"
sleep 16
apt_update
install_sftpgo
install_gcsfuse
get_external_ip

printf "\n\nOK. You can now connect into the machine in these ways:\n"
printf " export EXTERNAL_IP=\"${EXTERNAL_IP}\"\n"
printf " export VM_INSTANCE_NAME=\"${VM_INSTANCE_NAME}\"\n\n"
printf " gcloud compute ssh \"\${VM_INSTANCE_NAME}\" --project=\"\${GCP_PROJECT}\" --zone=\"\${GCE_VM_ZONE}\"\n\n"
printf " http://${EXTERNAL_IP}:8080/web/admin\n\n"
printf " sftp -oPort=2022 ${SFTP_USER}@${EXTERNAL_IP}\n\n"
