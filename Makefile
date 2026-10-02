TERRAFORM ?= terraform
.PHONY: check
check:
	$(TERRAFORM) fmt -check -recursive network
	$(TERRAFORM) -chdir=network init -backend=false -input=false -lockfile=readonly
	$(TERRAFORM) -chdir=network validate
	$(TERRAFORM) -chdir=network test
