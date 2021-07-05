
local-run:
	source env.sh && python local.py

lint:
	flake8 app > flake8-results.txt app || true
	flake8 riskstream >> flake8-results.txt riskstream  || true

acceptance-tests:
	pytest
