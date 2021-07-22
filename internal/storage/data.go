package storage

import (
	"github.com/jackc/pgtype"
)

type Data struct {
	// DnDSicCode                string        `db:"dnb_sic_code"`
	// DnDRiskIndicator          string        `db:"dnb_risk_indicator"`

	CRN               pgtype.Text `db:"crn"`
	Name              pgtype.Text `db:"company_name"`
	PrimaryTrade      pgtype.Text `db:"primary_trade"`
	RegisteredAddress pgtype.Text `db:"registered_address"`

	DnBBlueCollarEmployees    pgtype.Float8 `db:"dnb_blue_collar_employees"`
	DnBDelinquencyScore       string        `db:"dnb_delinquency_score"`
	DnBDunsNumber             string        `db:"dnb_duns_number"`
	DnBEmployees              pgtype.Float8 `db:"dnb_employees"`
	DnBEstimateNetWorth       pgtype.Float8 `db:"dnb_estimate_net_worth"`
	DnBEstimateSales          pgtype.Float8 `db:"dnb_estimate_sales"`
	DnBEstimateWorkingCapital pgtype.Float8 `db:"dnb_estimate_working_capital"`
	DnBFailureScore           pgtype.Float8 `db:"dnb_failure_score"`
	DnBMaxCredit              pgtype.Float8 `db:"dnb_max_credit"`
	DnBWageEstimate           pgtype.Float8 `db:"dnb_wage_estimate"`
	DnBWhiteCollarEmployees   pgtype.Float8 `db:"dnb_white_collar_employees"`
}
