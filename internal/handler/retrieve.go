package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/cytora/geospatial-lambda/internal/storage"
	"github.com/cytora/go-platform-utils/logging"
	"github.com/cytora/go-platform-utils/server"
	"github.com/jackc/pgtype"
)

type retrieveQueryParams struct {
	Groups string `schema:"groups"`
}

func (p *retrieveQueryParams) NormalizeGroups() []string {
	groups := strings.Split(p.Groups, ",")
	var normalisedGroups []string
	for i := range groups {
		group := groups[i]
		g := strings.ToLower(strings.TrimSpace(group))
		if len(g) > 0 {
			normalisedGroups = append(normalisedGroups, g)
		}
	}
	return normalisedGroups
}

type primaryTrade struct {
	Code        string `json:"code"`
	Description string `json:"description"`
}

func loadPrimaryTrade(data []byte) (*primaryTrade, error) {
	s := make(map[string]string)
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, err
	}
	pt := &primaryTrade{
		Code:        s["Code"],
		Description: s["Description"],
	}
	if pt.Code == "" && pt.Description == "" {
		return nil, fmt.Errorf("failed to unmarshal primary trade")
	}
	return pt, nil
}

type DnB struct {
	BlueCollarEmployees    float64 `json:"blue_collar_employees,omitempty"`
	DelinquencyScore       string  `json:"delinquency_score,omitempty"`
	DunsNumber             string  `json:"duns_number,omitempty"`
	Employees              float64 `json:"employees,omitempty"`
	EstimateNetWorth       float64 `json:"estimate_net_worth,omitempty"`
	EstimateSales          float64 `json:"estimate_sales,omitempty"`
	EstimateWorkingCapital float64 `json:"estimate_working_capital,omitempty"`
	FailureScore           float64 `json:"failure_score,omitempty"`
	MaxCredit              float64 `json:"max_credit,omitempty"`
	RiskIndicator          string  `json:"risk_indicator,omitempty"`
	SicCode                string  `json:"sic_code,omitempty"`
	WageEstimate           float64 `json:"wage_estimate,omitempty"`
	WhiteCollarEmployees   float64 `json:"white_collar_employees,omitempty"`
}

type RetrieveResponse struct {
	CRN               string        `json:"crn"`
	Name              string        `json:"company_name"`
	PrimaryTrade      *primaryTrade `json:"primary_trade"`
	RegisteredAddress string        `json:"registered_address"`
	DnB               *DnB          `json:"dnb,omitempty"`
}

func (h *Handler) Retrieve(r *http.Request) (int, interface{}, error) {
	ctx := context.Background()
	req, err := server.Unmarshal(r, nil)
	if err != nil {
		logging.Error(ctx, err, nil, "invalid request")
		return server.ErrorToResponse(ErrInvalidRequest, http.StatusBadRequest)
	}
	params := &retrieveQueryParams{}
	if err := req.UnmarshalQueryParams(ctx, params, true); err != nil {
		logging.Error(ctx, err, nil, "invalid query params")
		return server.ErrorToResponse(ErrInvalidQueryParams, http.StatusBadRequest)
	}
	if err := h.validator.Struct(params); err != nil {
		return server.ErrorToResponse(fmt.Errorf("%w %s", ErrInvalidQueryParams, err), http.StatusBadRequest)
	}
	crn := req.PathParams["crn"]
	groups := params.NormalizeGroups()
	data, err := h.storage.CompanyData(ctx, crn, groups)
	if err != nil {
		logging.Error(ctx, err, logging.Data{"crn": crn}, "error retrieving company's data")
		switch err {
		case storage.ErrNotFound:
			return server.ErrorToResponse(ErrNotFound, http.StatusNotFound)
		case storage.ErrInvalidGroups:
			return server.ErrorToResponse(ErrInvalidRequest, http.StatusBadRequest)
		default:
			return server.ErrorToResponse(ErrInternal, http.StatusInternalServerError)
		}
	}
	payload := &RetrieveResponse{
		CRN:               data.CRN.String,
		Name:              data.Name.String,
		RegisteredAddress: data.RegisteredAddress.String,
	}
	if data.PrimaryTrade.Status == pgtype.Present {
		pt, err := loadPrimaryTrade([]byte(data.PrimaryTrade.String))
		if err != nil {
			logging.Error(ctx, err, logging.Data{"crn": crn, "primary_trade": data.PrimaryTrade.String}, "failed to parse primary trade")
		} else {
			payload.PrimaryTrade = pt
		}
	}
	for i := range groups {
		group := groups[i]
		switch group {
		case "dnb":
			dnb := &DnB{}
			dnb.BlueCollarEmployees = data.DnBBlueCollarEmployees.Float
			dnb.DelinquencyScore = data.DnBDelinquencyScore
			dnb.DunsNumber = data.DnBDunsNumber
			dnb.Employees = data.DnBEmployees.Float
			dnb.EstimateNetWorth = data.DnBEstimateNetWorth.Float
			dnb.EstimateSales = data.DnBEstimateSales.Float
			dnb.FailureScore = data.DnBFailureScore.Float
			dnb.MaxCredit = data.DnBMaxCredit.Float
			dnb.WageEstimate = data.DnBWageEstimate.Float
			dnb.WhiteCollarEmployees = data.DnBWhiteCollarEmployees.Float
			payload.DnB = dnb
		}
	}
	return http.StatusOK, payload, nil
}
