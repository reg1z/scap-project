# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates OpenSCAP automation for applying SCAP (Security Content Automation Protocol) policies to an Oracle Linux 9 container. Oracle Linux is used instead of RHEL to avoid licensing issues while maintaining bug-for-bug compatibility with RHEL 9.

**Key principle**: DO NOT apply configurations without OpenSCAP. This project showcases OpenSCAP's auto-configuration capabilities.

## Architecture

Single container running on a Docker bridge network (`scap-network`):
- **oracle-host**: Oracle Linux 9 target container (the system being scanned/remediated)

The container is fully ephemeral with no persistent volumes.

SCAP content (DataStream XML files) can be downloaded from [public.cyber.mil](https://public.cyber.mil/stigs/scap/).

## Commands

### Initial Setup
```bash
./scripts/setup.sh
```
Pulls Oracle Linux 9 image, starts oracle-host container, configures SSH access.

### Container Management
```bash
docker-compose up -d      # Start container
docker-compose down       # Stop and remove container (fresh state on next up)
```

### SSH into Container
```bash
ssh root@<container-ip>  # password: scap123
```
Get container IP with: `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' oracle-host`

## Configuration

- `config/scap-content.conf`: Configuration for SCAP content path and profile
- `.env.example`: Environment variables template (copy to `.env`)

## Important Notes

- Container is ephemeral: `docker-compose down` removes all state, `docker-compose up -d` starts fresh
- SSH is configured on each `setup.sh` run; works reliably after any restart
- Default SSH password for oracle-host is `scap123` (demo purposes only)
- Do not edit README.md (per project guidelines in important.md)
