# Build via:
# docker build --no-cache -t bodgeit-sqlite -f Dockerfile .
# Run via:
# docker run --rm -p 8080:8080 -i -t bodgeit-sqlite

FROM tomcat:9.0-jdk8-temurin AS build

RUN apt-get update && \
	apt-get install -y ant && \
	rm -rf /var/lib/apt/lists/*

WORKDIR /opt/bodgeit
COPY . .
RUN ant build

FROM tomcat:9.0-jre8-temurin

COPY --from=build /opt/bodgeit/build/bodgeit.war /usr/local/tomcat/webapps/bodgeit.war
