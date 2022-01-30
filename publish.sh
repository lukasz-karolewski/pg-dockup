#!/bin/bash

docker login
docker build -t lkarolewski/pg-dockup:latest -t lkarolewski/pg-dockup:14 .
docker push lkarolewski/pg-dockup --all-tags
