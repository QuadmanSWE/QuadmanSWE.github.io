---
title: Azure blob storage from curl
published: true
---

# Upload large files from tiny devices to Azure blob storage

This week I got to work on something a bit different from my normal wheel house. 

I published [my source code here](https://github.com/QuadmanSWE/curl-blob) including examples for different auth schemes and different mechanisms of invokation

## Scope

The customer needed some fast help in solving how to upload files mounted on a device with limited RAM and very little maneuverability when it comes to adding software.

The limitations on the hardware specs posed the question:

Could we do it with just curl?

We briefly looked at something like scp but couldn't in time produce a binary that fit the CPU architecture.

So we ran with what we had: dd, curl and parts of openssl for cryptographic signing.

## Making plans

First I drew up how I wanted to interact with the software and what I know you need to interact with the Azure Blob Storage API.

- Accountname
- Credentials
- Container name
- Blob patch
- Local path

I knew I wanted to be able to run it in a docker container for testing to make sure I wasn't tricked by running on windows or wsl.

Quick and dirty, get alpine, add openssl and curl, call a shell script to make it happen once you mount the file you want to upload, let's go.

``` Dockerfile
FROM alpine
RUN apk add --no-cache curl openssl
COPY upload.sh /upload.sh
ENTRYPOINT ["/bin/sh", "/upload.sh"]
```

## First prototype

Github Copilot was friendly enough to get me started on a shell script that could perform the steps. But it was a tripped up by different versions in the API docs so I had to make some corrections.

[Documentation on rest PUT blob from Microsoft](https://learn.microsoft.com/en-us/rest/api/storageservices/put-blob)


Here is our first attempt to get a file to a blob storage container in one pass.

``` sh
#!/bin/sh
# upload.sh
set -e
# Arguments
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-$1}
STORAGE_ACCOUNT_KEY=${STORAGE_ACCOUNT_KEY:-$2}
STORAGE_CONTAINER=${STORAGE_CONTAINER:-$3}
BLOB_PATH=${BLOB_PATH:-$4}
FILE_PATH=${FILE_PATH:-$5}

BLOB_LENGTH=$(wc -c <$FILE_PATH)
BLOB_TYPE="BlockBlob"

# Construct the URL
URL="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${STORAGE_CONTAINER}/${BLOB_PATH}"
# Generate the headers
DATE_VALUE=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
STORAGE_SERVICE_VERSION="2019-12-12"
# Construct the CanonicalizedResource
CANONICALIZED_RESOURCE="/${STORAGE_ACCOUNT_NAME}/${STORAGE_CONTAINER}/${BLOB_PATH}"
# Construct the CanonicalizedHeaders
CANONICALIZED_HEADERS="x-ms-blob-type:${BLOB_TYPE}\nx-ms-date:${DATE_VALUE}\nx-ms-version:${STORAGE_SERVICE_VERSION}"
# Generate the signature
STRING_TO_SIGN="PUT\n\n\n${BLOB_LENGTH}\n\n\n\n\n\n\n\n\n${CANONICALIZED_HEADERS}\n${CANONICALIZED_RESOURCE}"
SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)
AUTHORIZATION_HEADER="SharedKey ${STORAGE_ACCOUNT_NAME}:${SIGNATURE}"
# Upload the file
curl -X PUT -T "${FILE_PATH}" -H "x-ms-blob-type: ${BLOB_TYPE}" -H "x-ms-date: ${DATE_VALUE}" -H "x-ms-version: ${STORAGE_SERVICE_VERSION}" -H "Authorization: ${AUTHORIZATION_HEADER}" ${URL}
# Terminate
exit 0
```

This worked well, the construction of the arguments were a bit finicky but we got there pretty quick. The error messages from the api were very helpful most of the time.

The authentication mechanism is that you sign the request (length, headers, resource) that you are using such that you prove that you have access to the private key to the storage account and that you want to perform the exact operation matching the signature. The API will do the same operation and compare the signatures.

## What if the files don't fit in RAM?

Right, hardware specs.

We came up with the idea of striping the files and uploading them one by one, but quickly found that Azure supports incremental uploads to a Append Blob.

Using dd to get the exact right chunk of data and piping it into curl.

Here was our resulting scheme, note that we need to sign each request to upload another block / chunk.

``` sh
##### removed for brevity
CHUNK_SIZE=${CHUNK_SIZE:-$6}
# Figures out if CHUNK_SIZE is null in which case we always to a single blob upload
if [ -z "$CHUNK_SIZE" ]; then
    CHUNK_SIZE=$BLOB_LENGTH
fi

if [ $BLOB_LENGTH -le $CHUNK_SIZE ]; then
    ##### Previous example, removed for brevity
    exit 0
else
    # empty append blob
    CONTENT_TYPE="application/octet-stream"
    BLOB_TYPE="AppendBlob"
    CANONICALIZED_HEADERS="x-ms-blob-type:${BLOB_TYPE}\nx-ms-date:${DATE_VALUE}\nx-ms-version:${STORAGE_SERVICE_VERSION}"
    STRING_TO_SIGN="PUT\n\n\n\n\n${CONTENT_TYPE}\n\n\n\n\n\n\n${CANONICALIZED_HEADERS}\n${CANONICALIZED_RESOURCE}"
    SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)
    AUTHORIZATION_HEADER="SharedKey ${STORAGE_ACCOUNT_NAME}:${SIGNATURE}"
    # Create an empty append blob
    curl -X PUT -H "Content-Type: ${CONTENT_TYPE}" -H "Content-Length: 0" -H "x-ms-blob-type: ${BLOB_TYPE}" -H "x-ms-date: ${DATE_VALUE}" -H "x-ms-version: ${STORAGE_SERVICE_VERSION}" -H "Authorization: ${AUTHORIZATION_HEADER}" ${URL}
end

# Upload the file in chunks
OFFSET=0
CHUNK_NUMBER=0
URL="${URL}?comp=appendblock"

while [ $(($OFFSET + $CHUNK_SIZE)) -le $BLOB_LENGTH ]; do
    CANONICALIZED_HEADERS="x-ms-blob-condition-appendpos:${OFFSET}\nx-ms-blob-condition-maxsize:${BLOB_LENGTH}\nx-ms-date:${DATE_VALUE}\nx-ms-version:${STORAGE_SERVICE_VERSION}"
    STRING_TO_SIGN="PUT\n\n\n${CHUNK_SIZE}\n\n${CONTENT_TYPE}\n\n\n\n\n\n\n${CANONICALIZED_HEADERS}\n${CANONICALIZED_RESOURCE}\ncomp:appendblock"
    SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)
    AUTHORIZATION_HEADER="SharedKey ${STORAGE_ACCOUNT_NAME}:${SIGNATURE}"
    dd if=$FILE_PATH bs=$CHUNK_SIZE count=1 skip=$CHUNK_NUMBER 2>/dev/null |
        curl -m 2 -X PUT --data-binary @- \
            -H "Content-Type: ${CONTENT_TYPE}" \
            -H "Content-Length: $CHUNK_SIZE" \
            -H "x-ms-blob-condition-maxsize: ${BLOB_LENGTH}" \
            -H "x-ms-blob-condition-appendpos: ${OFFSET}" \
            -H "x-ms-date: ${DATE_VALUE}" \
            -H "x-ms-version: ${STORAGE_SERVICE_VERSION}" \
            -H "Authorization: ${AUTHORIZATION_HEADER}" \
            "${URL}"
    OFFSET=$(($OFFSET + $CHUNK_SIZE))
    CHUNK_NUMBER=$(($CHUNK_NUMBER + 1))
done
# ...
```

This works super well as long as the chunks align with the entire blob size.
More often than not of course we will find that it doesn't, so we just calculate the last chunk size with modulo.

``` sh
# ... continuing on 
LAST_CHUNK_SIZE=$(($BLOB_LENGTH % $CHUNK_SIZE))
if [ $LAST_CHUNK_SIZE -gt 0 ]; then
    CANONICALIZED_HEADERS="x-ms-blob-condition-appendpos:${OFFSET}\nx-ms-blob-condition-maxsize:${BLOB_LENGTH}\nx-ms-date:${DATE_VALUE}\nx-ms-version:${STORAGE_SERVICE_VERSION}"
    STRING_TO_SIGN="PUT\n\n\n${LAST_CHUNK_SIZE}\n\n${CONTENT_TYPE}\n\n\n\n\n\n\n${CANONICALIZED_HEADERS}\n${CANONICALIZED_RESOURCE}\ncomp:appendblock"
    SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 -w0)
    AUTHORIZATION_HEADER="SharedKey ${STORAGE_ACCOUNT_NAME}:${SIGNATURE}"
    dd if=$FILE_PATH bs=$CHUNK_SIZE count=1 skip=$CHUNK_NUMBER 2>/dev/null |
        curl -m 2 -X PUT --data-binary @- \
            -H "Content-Type: ${CONTENT_TYPE}" \
            -H "Content-Length: $LAST_CHUNK_SIZE" \
            -H "x-ms-blob-condition-maxsize: ${BLOB_LENGTH}" \
            -H "x-ms-blob-condition-appendpos: ${OFFSET}" \
            -H "x-ms-date: ${DATE_VALUE}" \
            -H "x-ms-version: ${STORAGE_SERVICE_VERSION}" \
            -H "Authorization: ${AUTHORIZATION_HEADER}" \
            "${URL}"
fi
```

## Distributing signing keys to an entire storage account might not scale well with thousands of devices.

The central solution that the devices help out has a bit more power and a lot more flexibilty in adding new software.

By generating SAS tokens for the places where each device will push their blobs, we can tailor and distribute those tokens rather easily.

It simplifies the authentication process greatly too.

Examples of using this auth mechanism can be found in the github repo linked at the top.

Cheers.