# Builds a bootable iPXE USB image (BIOS + UEFI) with the Terraform-generated
# boot.ipxe chain script embedded, so PXE-booted machines go straight to matchbox.
#
# Build context must be the repo root (boot.ipxe lives in terraform/build/).
#
#   docker build -f tools/ipxe/Dockerfile --output type=local,dest=terraform/build .

FROM ubuntu:22.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
    liblzma-dev \
    genisoimage \
    isolinux \
    syslinux-common \
    mtools \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG IPXE_REPO=https://github.com/ipxe/ipxe.git
ARG IPXE_REF=master

RUN git clone --depth 1 --branch "${IPXE_REF}" "${IPXE_REPO}" /usr/src/ipxe

WORKDIR /usr/src/ipxe/src

COPY terraform/build/boot.ipxe /tmp/boot.ipxe

RUN make -j"$(nproc)" bin/ipxe.lkrn bin-x86_64-efi/ipxe.efi EMBED=/tmp/boot.ipxe \
    && ./util/genfsimg -o /tmp/ipxe.usb bin/ipxe.lkrn bin-x86_64-efi/ipxe.efi

FROM scratch AS export
COPY --from=build /tmp/ipxe.usb /ipxe.usb
