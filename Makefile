TF      := terraform
VARFILE ?= $(if $(wildcard $(TF)/terraform.tfvars),$(TF)/terraform.tfvars,$(TF)/terraform.tfvars.example)
TFARGS  := -var-file=$(VARFILE)

.PHONY: init plan apply bootstrap drift usb matchbox fmt validate lint shellcheck tflint

init:
	cd $(TF) && terraform init

plan:
	cd $(TF) && terraform plan $(TFARGS)

apply:
	cd $(TF) && terraform apply $(TFARGS)

# Stage 2: after the first control plane node has PXE booted.
# Bootstraps etcd, waits for cluster health, writes build/kubeconfig.
bootstrap:
	cd $(TF) && terraform apply $(TFARGS) -var bootstrap=true

# Push generated configs to running nodes (CP by static IP, workers discovered).
drift:
	cd $(TF) && terraform apply $(TFARGS) -var apply_to_running_nodes=true

# Build the iPXE boot USB with the generated chain script embedded.
usb:
	./tools/ipxe/build-ipxe-usb.sh

# Terraform-managed matchbox container.
matchbox:
	cd $(TF) && terraform apply $(TFARGS) -var manage_matchbox=true

fmt:
	cd $(TF) && terraform fmt -recursive

validate:
	cd $(TF) && terraform validate

lint: tflint shellcheck

tflint:
	cd $(TF) && tflint --init && tflint

shellcheck:
	shellcheck tools/*.sh
