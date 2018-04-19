# db install using setup image
FROM oe117-setup:latest AS db_install

# copy our response.ini in from our test install
COPY conf/response.ini /install/openedge/

#do a background progress install with our response.ini
RUN /install/openedge/proinst -b /install/openedge/response.ini -l silentinstall.log

###############################################

# actual db server image
FROM centos:7.3.1611

LABEL maintainer="Nick Heap (nickheap@gmail.com)" \
 version="0.1" \
 description="Database Server Image for OpenEdge 11.7.1" \
 oeversion="11.7.1"

# Add Tini
ENV TINI_VERSION v0.17.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini
ENTRYPOINT ["/tini", "--"]

# copy openedge files in
COPY --from=db_install /usr/dlc/ /usr/dlc/

# the directory for the database data
RUN mkdir -p /var/lib/openedge/data/ && mkdir -p /var/lib/openedge/base/ && mkdir -p /var/lib/openedge/code/
COPY base/procure.r /var/lib/openedge/base/

# add startup script
WORKDIR /usr/wrk

COPY scripts/ /usr/wrk/

# set required vars
ENV \
 TERM="xterm" \
 JAVA_HOME="/usr/dlc/jdk/bin" \
 PATH="$PATH:/usr/dlc/bin:/usr/dlc/jdk/bin" \
 PROPATH="/var/lib/openedge/base:/var/lib/openedge/code" \
 DLC="/usr/dlc" \
 WRKDIR="/usr/wrk" \
 PROCFG="" \
 OPENEDGE_DB="openedge" \
 OPENEDGE_MINPORT="20670" \
 OPENEDGE_MAXPORT="20700" \
 OPENEDGE_NUM_USERS="10" \
 OPENEDGE_DATE_FORMAT="dmy" \
 OPENEDGE_LOCKS="10000" \
 OPENEDGE_BUFFERS="2000" \
 OPENEDGE_BROKER_PORT="20666" \
 OPENEDGE_REBUILD= \
 OPENEDGE_BASE=empty4

# volume for database data
VOLUME /var/lib/openedge/data/
# volume for code such as triggers
VOLUME /var/lib/openedge/code/

HEALTHCHECK --interval=30s --timeout=5s \
  CMD ["healthcheck.sh"]

EXPOSE $OPENEDGE_BROKER_PORT $OPENEDGE_MINPORT-$OPENEDGE_MAXPORT

# Run start.sh under Tini
CMD ["/usr/wrk/start.sh"]

