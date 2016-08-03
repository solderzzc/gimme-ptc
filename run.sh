#!/bin/bash
docker run -it --rm --name my-running-script -v "$PWD/export":/usr/src/myapp/export  account-creater ruby account_creator.rb
