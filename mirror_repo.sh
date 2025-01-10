#!/bin/bash
# Fetch all new tags and push them to the mirror
# Fetch all specified branches (their name must be the same on both the mirror and upstream)

# Branches to be updated
target=("
main
master-kernel-build-2021
master-kernel-build-2022
main-kernel-build-2023
main-kernel-build-2024
")
# Remote
remote="https://android.googlesource.com/kernel/build"
r_name="aosp"

set -e
git remote | grep -q "$r_name" || git remote add "$r_name" "$remote"

for branch in ${target[@]}; do
  echo -e "\n[+] Updating $branch\n"
  git fetch "$r_name" "$branch"
  git push origin FETCH_HEAD:"refs/heads/$branch"
done

