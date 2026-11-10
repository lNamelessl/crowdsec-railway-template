FROM crowdsecurity/crowdsec:v1.8.2@sha256:2191029f82fce28971706f146cd0cde20a5d39dc9a0ccef7dfffc503d74bc707
# db_config fallbacks: the boot wrapper rewrites db_config from DB_* envs;
# these defaults keep the image self-sufficient if the variables are absent.
ENV DB_USER=crowdsec \
    DB_NAME=crowdsec
COPY crowdsec-railway-boot.sh /crowdsec-railway-boot.sh
ENTRYPOINT ["/bin/bash","/crowdsec-railway-boot.sh"]
