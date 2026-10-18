# Agent instructions — cloud-platform-network

The entry point for any coding agent working here. Read [README.md](README.md) first: it is the authoritative description of what the network creates, how releases work, and how services consume it. This file adds only what an agent must not get wrong.

## Purpose

Terraform for the one shared AWS network (`ap-south-1`) used by every cloud-platform service: the VPC, subnets, optional NAT gateway, S3 gateway and interface endpoints, and one Lambda security group per consumer. Services never copy this Terraform. They call the reusable workflow `.github/workflows/apply.yml` at a version tag and read the network state.

Current consumers: data-processing-service (`apply.yml@v1`, `lambda_security_groups` and `postgres_clients` entry `processing`). data-fetch-service runs its Lambdas outside the VPC and does not use this network.

## Repository map

- `network/`: the Terraform root: `main.tf`, `endpoints.tf`, `variables.tf` (defaults are the production configuration), `outputs.tf`, `versions.tf`.
- `network/tests/network.tftest.hcl`: mocked `terraform test` suite; it needs no AWS credentials.
- `.github/workflows/ci.yml`: the local checks on every pull request and push to `main`.
- `.github/workflows/apply.yml`: the `Network` workflow. It plans on a push to `main`, applies on a `v*` tag push, and is the reusable workflow services call.
- `.github/workflows/destroy.yml`: the manual `Destroy network` workflow.

## Commands

- `make check`: `terraform fmt -check`, `validate`, and the mocked test suite with Terraform 1.16.4; pass `TERRAFORM=/path/to/terraform` when it is not on `PATH`. Needs network access for the provider, no AWS credentials.

Run `make check` before every PR and report what ran and what passed. Never run `terraform apply`, `destroy`, or any command with AWS credentials locally: changes reach AWS only through the workflows.

## Invariants

- **One owner, one state.** The network state is `network/terraform.tfstate` in the bucket `cloud-platform-network-terraform-state`. Never add a second state, workspace, or environment.
- **Outputs are a contract.** Services read the outputs listed in the README. Renaming or removing one, or changing its shape, breaks consumers: add the new output first, move every consumer, then remove the old one in a later tag.
- **Releases are tags.** A merge to `main` only plans. A `v*` tag applies. Every consumer must then move to the same tag, because a service still on an older tag undoes the change when it deploys. Say in the PR which tag the change needs and which consumers must move.
- **No NAT by default.** `nat_gateway` stays `false` unless the owner decides otherwise (data-processing-service decision 0001). A consumer that needs another AWS API adds its short name to `interface_endpoint_services`; one that needs the internet and no private resource runs outside the VPC instead.
- **Cost and availability are visible.** Interface endpoints and a NAT gateway are billed hourly, and the default single endpoint zone is a single point of failure. A PR that adds an endpoint, a zone, or NAT states the cost and availability effect.
- **New consumers come through variables.** A new security group or endpoint changes the defaults in `network/variables.tf` and adds a case to the test suite. Never hard-code a consumer elsewhere.
- **Destroy is manual and confirmed.** Never weaken the `destroy` confirmation, and never remove the state bucket.

## Keeping guidance current

Update the README in the same PR as any change to resources, variables, outputs, workflows, or the release steps. Update the consumer list above when a service starts or stops using the network. Keep this file short. `CLAUDE.md` only imports this file, so Claude Code and other agents read the same instructions.
