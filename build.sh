#!/bin/sh
set -e

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_GITHUB_URL="https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master"
HAPROXY_BRANCHES="1.5 1.6 1.7 1.8 1.9 2.0 2.1"
HAPROXY_CURRENT_BRANCH="2.0"
PUSH="no"
HAPROXY_UPDATED=""

for i in $HAPROXY_BRANCHES; do
    echo "Building HAProxy $i"

    DOCKERFILE="$i/Dockerfile"
    HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    ./update.sh "$i"

    HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    if [ "x$1" != "xforce" ]; then
        if [ "$HAPROXY_MINOR_OLD" = "$HAPROXY_MINOR" ]; then
            echo "No new releases, not building $i branch"
            continue
        else
            PUSH="yes"
        fi
    else
        PUSH="yes"
    fi

    HAPROXY_UPDATED="$HAPROXY_UPDATED $HAPROXY_MINOR"

    docker pull $(awk '/^FROM/ {print $2}' "$DOCKERFILE")

    docker build -t "$DOCKER_TAG:$HAPROXY_MINOR" "$i"
    docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:$i"

    if [ "$i" = "$HAPROXY_CURRENT_BRANCH" ]; then
        docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
    fi

    docker run -it --rm "$DOCKER_TAG:$HAPROXY_MINOR" /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

    git tag -d "$HAPROXY_MINOR" || true
    git tag "$HAPROXY_MINOR"
done

if [ "$PUSH" = "no" ]; then
	exit 0
fi

echo "# Supported tags and respective \`Dockerfile\` links\n" > README.md
for i in $(awk '/^ENV HAPROXY_MINOR/ {print $NF}' */Dockerfile| sort -n -r); do
	short=$(echo $i | cut -d. -f1-2 |cut -d- -f1)
	if [ "$short" = "$HAPROXY_CURRENT_BRANCH" ]; then
		if [ "$short" = "$i" ]; then
			final="-\t[\`$i\`, \`latest\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
		else
			final="-\t[\`$i\`, \`$short\`, \`latest\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
		fi
	else
		if [ "$short" = "$i" ]; then
			final="-\t[\`$i\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
		else
			final="-\t[\`$i\`, \`$short\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
		fi
	fi
	echo "$final" >> README.md
done
echo >> README.md
cat README_short.md >> README.md

git commit -a -m "Automated commit triggered by $HAPROXY_UPDATED release(s)"
git push
git push --tags
