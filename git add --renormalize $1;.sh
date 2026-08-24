#!/bin/sh
cd $1;

git add --renormalize *;
git commit -m "Dummy renormalize for git lfs";
git merge -X theirs develop;