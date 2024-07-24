# Buildbot worker for building MariaDB
#
# Provides a base RHEL-7 image with latest buildbot worker installed
# and MariaDB build dependencies

ARG BASE_IMAGE
FROM registry.access.redhat.com/$BASE_IMAGE
LABEL maintainer="MariaDB Buildbot maintainers"

# Install updates and required packages
RUN --mount=type=secret,id=rhel_orgid,target=/run/secrets/rhel_orgid \
    --mount=type=secret,id=rhel_keyname,target=/run/secrets/rhel_keyname \
    sed -i 's/\(def in_container():\)/\1\n    return False/g' /usr/lib64/python*/*-packages/rhsm/config.py \
    && subscription-manager register \
         --org="$(cat /run/secrets/rhel_orgid)" \
         --activationkey="$(cat /run/secrets/rhel_keyname)" \
    && rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
    && yum -y upgrade \
    # the following is needed in case the subscription-manager was upgraded by the previous step \
    && sed -i 's/\(def in_container():\)/\1\n    return False/g' /usr/lib64/python*/*-packages/rhsm/config.py \
    && subscription-manager unregister \
    && subscription-manager clean \
    && subscription-manager register \
         --org="$(cat /run/secrets/rhel_orgid)" \
         --activationkey="$(cat /run/secrets/rhel_keyname)" \
    && subscription-manager repos --enable=rhel-7-server-optional-rpms \
    && yum-builddep -y mariadb-server \
    && yum -y install \
    @development \
    boost-devel \
    bzip2 \
    bzip2-devel \
    ccache \
    check-devel \
    cmake3 \
    cracklib-devel \
    createrepo \
    curl-devel \
    galera \
    java-latest-openjdk-devel \
    java-latest-openjdk \
    jemalloc-devel \
    libffi-devel \
    libxml2-devel \
    lz4-devel \
    perl-autodie \
    perl-Net-SSLeay \
    pcre2-devel \
    python3-pip \
    rpmlint \
    snappy-devel \
    systemd-devel \
    wget \
    && if [ "$(arch)" = "ppc64le" ]; then \
        subscription-manager repos --enable rhel-7-for-power-le-optional-rpms; \
        yum -y install python3-devel; \
    fi \
    && yum clean all \
    && subscription-manager unregister \
    # We can't use old cmake version (from @development package) \
    && yum -y remove cmake \
    && ln -sf /usr/bin/cmake3 /usr/bin/cmake \
    && curl -sL "https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_$(uname -m)" >/usr/local/bin/dumb-init \
    && chmod +x /usr/local/bin/dumb-init

ENV CRYPTOGRAPHY_ALLOW_OPENSSL_102=1

ENV WSREP_PROVIDER=/usr/lib64/galera/libgalera_smm.so
