FROM tianon/toybox:0.8.4


COPY scripts /tmp/scripts
COPY init-script /init-script
COPY peer-finder /tmp/scripts/peer-finder
COPY tini /tmp/scripts/tini

ENTRYPOINT ["/init-script/run.sh"]
