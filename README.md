# cloud-platform-network

One shared AWS network for every cloud-platform service, with a single owner. Services do not copy this Terraform: their deployment calls the reusable workflow here, which creates the network on the first call and changes nothing on later calls, then they read its outputs.

The network is created in `ap-south-1`. Check the latest `Shared network` and `Destroy network` workflow runs for whether it currently exists.

## What it creates

| Resource | Default |
|---|---|
| VPC | `10.20.0.0/16`, DNS support and hostnames on |
| Subnets | One public and one private `/20` in each of `ap-south-1a` and `ap-south-1b` |
| NAT gateway | One, in the first zone, used by every private subnet |
| S3 gateway endpoint | On every private route table; allows only this account's buckets |
| Interface endpoints | SQS and CloudWatch Logs, private DNS on, HTTPS from the VPC only |
| Lambda security groups | One per consumer in `lambda_security_groups` (default `fetch`): HTTPS egress only, no ingress |

A single NAT gateway means an outage of its zone stops outbound internet access for the whole VPC until it recovers. The NAT gateway and interface endpoints are billed hourly from creation.

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

`vpc_id`, `vpc_cidr`, `public_subnet_ids_by_az`, `private_subnet_ids_by_az`, `private_route_table_ids_by_az`, `nat_gateway_ids_by_az` (every zone maps to the one gateway), `s3_endpoint_id`, `interface_endpoint_ids`, `sqs_endpoint_id`, `logs_endpoint_id`, `lambda_security_group_ids`, `fetch_lambda_security_group_id`.

## State

The workflow creates the bucket `cloud-platform-network-terraform-state` if this account does not have it (versioned, encrypted, no public access) and locks with an S3 lock file, so two pipelines cannot apply at once. If the bucket name is owned by another account the workflow fails rather than choosing a different name.

## Removing the network

The manual `Destroy network` workflow in this repository removes every resource in the network state after you type `destroy` to confirm. It keeps the state bucket, so the next apply re-creates the network. Any service whose Lambdas or endpoints still use the VPC will block the destroy or be left without a network.

## Adding a consumer

A new service that needs its own Lambda security group or another interface endpoint changes the defaults of `lambda_security_groups` or `interface_endpoint_services` in `network/variables.tf` through a pull request here, followed by a new version tag. Callers move to the new tag deliberately.

## Local checks

`make check TERRAFORM=/path/to/terraform` runs `fmt -check`, `validate`, and the mocked `terraform test` suite with Terraform 1.16.4. It needs network access for the provider and no AWS credentials.
