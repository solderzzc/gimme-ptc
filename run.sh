#!/bin/bash
docker run -it --rm --name account-creator-script -v "$PWD/export":/usr/src/app/export  account-creater ruby account_creator.rb
