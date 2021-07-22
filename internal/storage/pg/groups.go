package pg

import (
	"fmt"
	"strings"
)

const (
	baseGroup = "base"
	dnbGroup  = "dnb"

	baseGroupFields = `
	"crn",
	"company_name",
	"primary_trade",
	"registered_address"`

	dnbGroupFields = `
	"dnb_blue_collar_employees",
	"dnb_delinquency_score",
	"dnb_duns_number",
	"dnb_employees",
	"dnb_estimate_net_worth",
    "dnb_estimate_sales",
	"dnb_estimate_working_capital",
	"dnb_failure_score",
	"dnb_max_credit",
	"dnb_wage_estimate",
	"dnb_white_collar_employees"`

	/*
		"dnb_risk_indicator",
		"dnb_sic_code",

	*/

	retrieveQuery = `select %s from entries_crn where crn=$1`
)

var (
	groupsFields = map[string]string{
		baseGroup: baseGroupFields,
		dnbGroup:  dnbGroupFields,
	}
)

func validateGroups(groups []string) bool {
	for i := range groups {
		group := groups[i]
		if _, ok := groupsFields[group]; !ok {
			return false
		}
	}
	return true
}

func generateQuery(groups []string) string {
	b := strings.Builder{}
	separator := ""
	for i := range groups {
		group := groups[i]
		groupFields, ok := groupsFields[group]
		if !ok {
			continue
		}
		b.WriteString(separator)
		b.WriteString(groupFields)
		separator = ","
	}
	return fmt.Sprintf(retrieveQuery, b.String())
}
