.PHONY: *

APP=
APPS=\
	releng_frontend \
	releng_clobberer \
	shipit_frontend \
	shipit_dashboard

TOOL=
TOOLS=\
	pypi2nix \
	awscli \
	node2nix \
	mysql2sqlite \
	mysql2pgsql


APP_DEV_PORT_releng_frontend=8001
APP_DEV_PORT_releng_clobberer=8002
APP_DEV_PORT_shipit_frontend=8003
APP_DEV_PORT_shipit_dashboard=8004

APP_DEV_ENV_releng_frontend=NEO_CLOBBERER_URL=https://localhost:$(APP_DEV_PORT_releng_clobberer)
APP_DEV_ENV_shipit_frontend=NEO_DASHBOARD_URL=https://localhost:$(APP_DEV_PORT_shipit_dashboard)

APP_STAGING_HEROKU_releng_clobberer=releng-staging-clobberer
APP_STAGING_HEROKU_shipit_dashboard=shipit-staging-dashboard

APP_STAGING_S3_docs=releng-staging-docs
APP_STAGING_S3_releng_frontend=releng-staging-frontend
APP_STAGING_S3_shipit_frontend=shipit-staging-frontend

APP_PRODUCTION_HEROKU_releng_clobberer=releng-production-clobberer
APP_PRODUCTION_HEROKU_shipit_dashboard=shipit-production-dashboard

APP_PRODUCTION_S3_docs=releng-production-docs
APP_PRODUCTION_S3_releng_frontend=releng-production-frontend
APP_PRODUCTION_S3_shipit_frontend=shipit-production-frontend


help:
	@echo "TODO: need to write help for commands"


nix:
	@if [[ -z "`which nix-build`" ]]; then \
		curl https://nixos.org/nix/install | sh; \
		source $HOME/.nix-profile/etc/profile.d/nix.sh; \
	fi


develop: nix require-APP
	nix-shell nix/default.nix -A $(APP) --run $$SHELL




develop-run: require-APP develop-run-$(APP)

develop-run-BACKEND: nix require-APP 
	DEBUG=true \
	CACHE_TYPE=filesystem \
	CACHE_DIR=$$PWD/src/$(APP)/cache \
	DATABASE_URL=sqlite:///$$PWD/app.db \
	APP_SETTINGS=$$PWD/src/$(APP)/settings.py \
		nix-shell nix/default.nix -A $(APP) \
		--run "gunicorn $(APP):app --bind 'localhost:$(APP_DEV_PORT_$(APP))' --certfile=nix/dev_ssl/server.crt --keyfile=nix/dev_ssl/server.key --workers 2 --timeout 3600 --reload --log-file -"

develop-run-FRONTEND: nix require-APP 
	nix-shell nix/default.nix --pure -A $(APP) \
		--run "$(APP_DEV_ENV_$(APP)) neo start --port $(APP_DEV_PORT_$(APP)) --config webpack.config.js"

develop-run-releng_clobberer: develop-run-BACKEND
develop-run-releng_frontend: develop-run-FRONTEND

develop-run-shipit_dashboard: develop-run-BACKEND
develop-run-shipit_frontend: develop-run-FRONTEND






build-apps: $(foreach app, $(APPS), build-app-$(app))

build-app: require-APP build-app-$(APP)

build-app-%: nix
	nix-build nix/default.nix -A $(subst build-app-,,$@) -o result-$(subst build-app-,,$@)



docker: require-APP docker-$(APP)

docker-%: nix
	rm -f result-$@
	nix-build nix/docker.nix -A $(subst docker-,,$@) -o result-$@



deploy-staging-all: $(foreach app, $(APPS), deploy-staging-$(app)) deploy-staging-docs

deploy-staging: require-APP deploy-staging-$(APP)

deploy-staging-HEROKU: require-APP
	if [[ -n "`docker images -q $(APP)`" ]]; then \
		docker rmi -f `docker images -q $(APP)`; \
	fi
	cat result-docker-$(APP) | docker load
	docker tag `docker images -q $(APP) registry.heroku.com/$(APP_STAGING_HEROKU_$(APP))
	docker push registry.heroku.com/$(APP_STAGING_HEROKU_$(APP))

deploy-staging-S3: require-AWS require-APP build-tool-awscli build-app-$(APP)
	./result-tool-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read  \
		result-$(APP)/ \
		s3://$(APP_STAGING_S3_$(APP))

deploy-staging-releng_clobberer: deploy-staging-HEROKU
deploy-staging-shipit_dashboard: deploy-staging-HEROKU

deploy-staging-docs: deploy-staging-S3
deploy-staging-releng_frontend: deploy-staging-S3
deploy-staging-shipit_frontend: deploy-staging-S3





deploy-production-all: $(foreach app, $(APPS), deploy-production-$(app)) deploy-production-docs

deploy-production: require-APP deploy-production-$(APP)

deploy-production-HEROKU: require-APP
	if [[ -n "`docker images -q $(APP)`" ]]; then \
		docker rmi -f `docker images -q $(APP)`; \
	fi
	cat result-docker-$(APP) | docker load
	docker tag `docker images -q $(APP) registry.heroku.com/$(APP_PRODUCTION_HEROKU_$(APP))
	docker push registry.heroku.com/$(APP_PRODUCTION_HEROKU_$(APP))

deploy-production-S3: require-AWS require-APP build-tool-awscli build-app-$(APP)
	./result-tool-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read  \
		result-$(APP)/ \
		s3://$(APP_PRODUCTION_S3_$(APP))

deploy-production-releng_clobberer: deploy-production-HEROKU
deploy-production-shipit_dashboard: deploy-production-HEROKU

deploy-production-docs: deploy-production-S3
deploy-production-releng_frontend: deploy-production-S3
deploy-production-shipit_frontend: deploy-production-S3




update-all: \
	$(foreach tool, $(TOOLS), update-tools.$(tool)) \
	$(foreach app, $(APPS), update-$(app))

update: require-APP update-$(APP)

update-%: nix
	nix-shell nix/update.nix --argstr pkg $(subst update-,,$@)





build-tools: $(foreach tool, $(TOOLS), build-tool-$(tool))

build-tool: require-TOOL build-tool-$(TOOL)

build-tool-%: nix
	nix-build nix/default.nix -A tools.$(subst build-tool-,,$@) -o result-tool-$(subst build-tool-,,$@)





build-docs: nix
	nix-build nix/default.nix -A releng_docs -o result-docs


# --- helpers


require-TOOL:
	@if [[ -z "$(TOOL)" ]]; then \
		echo ""; \
		echo "You need to specify which TOOL to build, eg:"; \
		echo "  make build-tool TOOL=awscli"; \
		echo "  ..."; \
		echo ""; \
		echo "Available TOOLS are: "; \
		for tool in $(TOOLS); do \
			echo " - $$tool"; \
		done; \
		echo ""; \
		exit 1; \
	fi
require-APP:
	@if [[ -z "$(APP)" ]]; then \
		echo ""; \
		echo "You need to specify which APP, eg:"; \
		echo "  make develop APP=releng_clobberer"; \
		echo "  make build-app APP=releng_clobberer"; \
		echo "  ..."; \
		echo ""; \
		echo "Available APPS are: "; \
		for app in $(APPS); do \
			echo " - $$app"; \
		done; \
		echo ""; \
		exit 1; \
	fi


require-AWS:
	@if [[ -z "$$AWS_ACCESS_KEY_ID" ]] || \
		[[ -z "$$AWS_SECRET_ACCESS_KEY" ]]; then \
		echo ""; \
		echo "You need to specify AWS credentials, eg:"; \
		echo "  make deploy-production-releng_clobberer \\"; \
	    echo "       AWS_ACCESS_KEY_ID=\"...\" \\"; \
		echo "       AWS_SECRET_ACCESS_KEY=\"...\""; \
		echo ""; \
		echo ""; \
		exit 1; \
	fi

all: build-apps build-tools
