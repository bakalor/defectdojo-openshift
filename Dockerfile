FROM ubuntu:16.04
MAINTAINER Igor Bakalo <bigorigor.ua@gmail.com>

# Setup application environment variables

ARG DBTYPE="1"
ARG SQLHOST=""
ARG SQLPORT=""
ARG SQLUSER=""
ARG SQLPWD=""
ARG DBNAME=""
ARG APPFQDN=""

ENV DBTYPE=$DBTYPE
ENV SQLHOST=$SQLHOST
ENV SQLPORT=$SQLPORT
ENV SQLUSER=$SQLUSER
ENV SQLPWD=$SQLPWD
ENV DBNAME=$DBNAME
ENV APPFQDN=$APPFQDN

# Update and install basic requirements;

RUN apt-get update && apt-get install -y \
    mysql-client \
    sudo \
    curl \
    git \
    expect \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create application user
RUN adduser --disabled-password --gecos "DefectDojo" dojo

# Upload The DefectDojo application
WORKDIR /opt
RUN git clone https://github.com/DefectDojo/django-DefectDojo.git

WORKDIR /opt/django-DefectDojo
# Install application dependancies
RUN /bin/bash -c "source entrypoint_scripts/common/dojo-shared-resources.sh && install_os_dependencies"

# Give the app user sudo permissions and switch executing user
RUN echo "dojo    ALL=(ALL:ALL)   NOPASSWD: ALL" > /etc/sudoers.d/sudo_dojo

# Upload and run script for dynamic creation of a passwd file entry with the container’s user ID
COPY uid_determination.bash /uid_determination.bash
RUN chmod u=rwx,g=u+x /uid_determination.bash

# Upload DefectDojo setup script
COPY defect_dojo_prerun_setup.bash ./defect_dojo_prerun_setup.bash
RUN chmod +x defect_dojo_prerun_setup.bash

USER dojo:dojo

# Start the DB server and run the app
ENTRYPOINT \
    # User name recognition at runtime
    sudo /uid_determination.bash \
    # DefectDojo interconnection settings configuration
    && /opt/django-DefectDojo/defect_dojo_prerun_setup.bash \
    # Update ALLOWED_HOSTS with actual route
    && sed -e 's/ALLOWED_HOSTS.*/ALLOWED_HOSTS = [" $APPFQDN "]/g' dojo/settings/settings.py \
    # Start application's components
    && (celery -A dojo worker -l info --concurrency 3 >> /opt/django-DefectDojo/worker.log 2>&1 &) \
    && (celery beat -A dojo -l info  >> /opt/django-DefectDojo/beat.log 2>&1 &) \
    && (python manage.py runserver 0.0.0.0:8000 >> /opt/django-DefectDojo/dojo.log 2>&1)
