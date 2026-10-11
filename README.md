# cloud-platform-network

One shared AWS network for every cloud-platform service, with a single owner. Services do not copy this Terraform: their deployment calls the reusable workflow here, which creates the network on the first call and changes nothing on later calls, then they read its outputs.

The network is created in `ap-south-1`. Check the latest `Shared network` and `Destroy network` workflow runs for whether it currently exists.

## What it creates

| Resource | Default |
|---|---|
| VPC | `10.20.0.0/16`, DNS support and hostnames on |
| Subnets | One public and one private `/20` in each of `ap-south-1a` and `ap-south-1b` |
| NAT gateway | None by default (`nat_gateway = false`). When on, one in the first zone serves every private subnet |
| S3 gateway endpoint | On every private route table; allows only this account's buckets |
| Interface endpoints | SQS and Secrets Manager by default (`interface_endpoint_services`), in the first zone only by default (`interface_endpoint_zones`; Lambdas in other zones reach them across zones), private DNS on, HTTPS from the VPC only |
| Lambda security groups | One per consumer in `lambda_security_groups` (default `processing`), no ingress. HTTPS egress goes to the VPC (interface endpoints) and the S3 prefix list, or anywhere when NAT is on. Consumers in `postgres_clients` (default `processing`) may also reach PostgreSQL (5432) inside the VPC |

Without NAT the private subnets have no internet route: a Lambda in them reaches only the VPC, S3, and the services that have an interface endpoint. The processing migration Lambda reads the RDS-managed master secret through the Secrets Manager endpoint; the other functions sign their database IAM tokens locally. A call to another AWS API (STS, KMS, CloudWatch Logs) times out until its short name is added to `interface_endpoint_services`. Services that need the internet and no private resource, such as data-fetch-service, run their Lambdas outside the VPC instead. Interface endpoints are billed hourly per zone from creation. With the default single endpoint zone, an outage of that zone cuts every Lambda in the VPC off from those services; list both zones in `interface_endpoint_zones` when a consumer must survive it. If `nat_gateway` is turned on, its gateway and Elastic IP are billed hourly too, and an outage of its zone stops outbound internet access for the whole VPC until it recovers.

## Releasing a change

1. Merge the pull request. CI runs the local checks, and the `Network` workflow plans against the live network without changing it; read the plan in its log.
2. Push a tag for the merged commit: `git tag v2 <commit> && git push origin v2`. The `Network` workflow plans and applies that commit.
3. Move every service's `uses: ...apply.yml@vN` to the new tag. All services share one network state, so keep them on the same tag: a service still on an older tag would undo the change when it deploys.

The `Network` workflow needs this repository's `AWS_ROLE_TO_ASSUME` secret, and the role's OIDC trust must allow this repository's `main` branch and `v*` tags as well as the calling services.

## Using it from a service repository

```yaml
jobs:
  network:
    uses: maverickuser/cloud-platform-network/.github/workflows/apply.yml@v1
    secrets:
      AWS_ROLE_TO_ASSUME: ${{ secrets.AWS_ROLE_TO_ASSUME }}
  deploy:
    needs: network
    # ... the service's own Terraform, reading the state below
```

The AWS role is assumed with the calling repository's identity, so the role's OIDC trust must already allow the caller. Pass `apply: false` to plan only. Keep `network_ref` equal to the ref in `uses:`; both default to `v1`.

The service's Terraform then reads the network state:

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "cloud-platform-network-terraform-state"
    key    = "network/terraform.tfstate"
    region = "ap-south-1"
  }
}
```

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids_by_az`, `private_subnet_ids_by_az`, `private_route_table_ids_by_az`, `nat_gateway_ids_by_az` (every zone maps to the one gateway; empty without NAT), `s3_endpoint_id`, `interface_endpoint_ids`, `interface_endpoint_zones`, `sqs_endpoint_id`, `lambda_security_group_ids`.

## State

The workflow creates the bucket `cloud-platform-network-terraform-state` if this account does not have it (versioned, encrypted, no public access) and locks with an S3 lock file, so two pipelines cannot apply at once. If the bucket name is owned by another account the workflow fails rather than choosing a different name.

## Removing the network

The manual `Destroy network` workflow in this repository removes every resource in the network state after you type `destroy` to confirm. It keeps the state bucket, so the next apply re-creates the network. Any service whose Lambdas or endpoints still use the VPC will block the destroy or be left without a network.

## Adding a consumer

A new service that needs its own Lambda security group or another interface endpoint changes the defaults of `lambda_security_groups` or `interface_endpoint_services` in `network/variables.tf` through a pull request here, followed by a new version tag. Callers move to the new tag deliberately.

## Local checks

`make check TERRAFORM=/path/to/terraform` runs `fmt -check`, `validate`, and the mocked `terraform test` suite with Terraform 1.16.4. It needs network access for the provider and no AWS credentials.
