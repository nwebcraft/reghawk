.PHONY: build deploy invoke logs test-rss test-line test-gemini setup

# ============================================================
# RegHawk - コマンド一覧
# ============================================================

# --- SAM ---
build:
	sam build

deploy:
	sam deploy --guided

deploy-fast:
	sam build && sam deploy

invoke:
	sam remote invoke RegHawkWatcher

invoke-local:
	sam local invoke RegHawkWatcher \
		--event events/scheduled.json \
		--env-vars env.json

logs:
	sam logs --name RegHawkWatcher --tail

# --- テスト ---
test-rss:
	ruby rss_url_checker.rb
	ruby rss_fetcher_prototype.rb

test-line:
	ruby line_notifier.rb test

test-gemini:
	ruby gemini_test.rb

test-all: test-rss test-line test-gemini

# --- DB ---
db-migrate:
	ruby db_migrate.rb

db-reset:
	ruby db_migrate.rb reset

db-schema:
	ruby db_migrate.rb schema

# --- セットアップ ---
setup:
	@echo "=== RegHawk セットアップ ==="
	@echo "1. env.json に接続情報を記入"
	@echo "2. make db-migrate"
	@echo "3. make test-rss"
	@echo "4. make test-line"
	@echo "5. make test-gemini"
	@echo "6. make build"
	@echo "7. make deploy"
	@echo "=========================="
