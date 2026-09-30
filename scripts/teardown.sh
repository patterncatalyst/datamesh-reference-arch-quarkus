#!/usr/bin/env bash
#
# teardown.sh — delete the minikube profile and free its resources.
#
# This is destructive: all data, all manifests, all state in the profile is
# gone after this runs. Use when you want to start fresh (also: pass --replace
# to setup-profile.sh, which does this + recreates in one step).

set -euo pipefail
PROFILE_NAME="datamesh"

printf '==> About to delete minikube profile: %s\n' "$PROFILE_NAME"
printf '    This will wipe the cluster, all images, all PVs. Continue? [y/N] '
read -r answer
[[ "$answer" =~ ^[Yy] ]] || { printf 'Aborted.\n'; exit 1; }

minikube delete -p "$PROFILE_NAME"
printf '==> Profile %s deleted.\n' "$PROFILE_NAME"
