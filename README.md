# Setting uop an SFTP server in Google Compute Engine

The goal here is to be able to set up an SFTP server , at least for demo purposes, in Google Compute Engine.

This is not a hardened SFTP solution. Just an illustration of what is possible and how to do it.

Reference: https://stackoverflow.com/a/64143107

## Getting set up

1. Modify the [`env.sh`](./env.sh) file, setting your own project, region, and zone.

2. Run the setup script
   ```
   ./setup-sftp-server-example.sh
   ```
   This script performs a number of steps, using the gcloud command line tool:
   - create a GCS bucket
   - create a Service Account, and grant permissions on that bucket to the SA
   - create a VM instance, using Debian, that uses that service account as its identity
   - create firewall rules allowing SFTP access into the VM instance
   - install sftp onto that VM instance, create a testuser, and configure sshd to allow that user to login
   - install gcsfuse onto that instance. This is a filesystem that can use GCS as backing store.

   The final lines of output of the script will look something like this:
   ```
   OK. You can now SSH into the machine this way:
      export VM_INSTANCE_NAME="sftp-example-instance-u0aptk-20241008-233550"
      export EXTERNAL_IP="35.127.123.44"

      gcloud compute ssh "${VM_INSTANCE_NAME}" --project="${GCP_PROJECT}" --zone="${GCE_VM_ZONE}"
      sftp -oPort=22 testuser@${EXTERNAL_IP}
   ```

## Using it

After the setup completes, you should have a server with an ephemeral IP address. You can then
sftp into that server and drop things into the right directory, and the files will be stored in GCS.

```
export EXTERNAL_IP="35.127.123.44"
sftp -oPort=22 testuser@${EXTERNAL_IP}
```

The password is `Secret123`.

You can then cd into the `gcs` directory, and put files into it:
```
cd gcs
put README.md
exit
```

If you then visit
[https://console.cloud.google.com/storage/browser](https://console.cloud.google.com/storage/browser),
and select your project, you should be able to see the bucket
`sftp-server-example-bucket`, with the obejcts (files) you have uploaded via
FTP.


## Cleaning up

To remove everything the setup script provisions, runt he cleanup script:
```
./clean-sftp-server-example.sh
```
