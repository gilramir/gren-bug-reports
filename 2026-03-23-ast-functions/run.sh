#!/bin/bash
#
set -e

gren make --output=app Main

node app files/Example.gren
