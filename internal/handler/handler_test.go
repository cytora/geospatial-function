package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/gorilla/mux"
	"github.com/jackc/pgtype"
	"github.com/stretchr/testify/assert"

	"github.com/cytora/geospatial-lambda/internal/storage"
	"github.com/cytora/geospatial-lambda/internal/storage/mock"
	"github.com/cytora/go-platform-utils/common"
	"github.com/cytora/go-platform-utils/server"
)

func TestHandler_Retrieve(t *testing.T) {

	tests := []struct {
		name   string
		auth   *common.AuthData
		crn    string
		groups []string

		stgErr     error
		stgResults *storage.Data

		expectedStatus  int
		expectedResults *RetrieveResponse
	}{
		{
			name:   "base",
			auth:   &common.AuthData{PartnerID: "test"},
			crn:    "000111222",
			groups: []string{},

			stgErr: nil,
			stgResults: &storage.Data{
				CRN: pgtype.Text{String: "000111222", Status: pgtype.Present},
			},

			expectedStatus: http.StatusOK,
			expectedResults: &RetrieveResponse{
				CRN: "000111222",
			},
		},
		{
			name:   "primary trade",
			auth:   &common.AuthData{PartnerID: "test"},
			crn:    "000111222",
			groups: []string{},

			stgErr: nil,
			stgResults: &storage.Data{
				CRN: pgtype.Text{
					String: "000111222",
					Status: pgtype.Present,
				},
				PrimaryTrade: pgtype.Text{
					String: `{"Code": "00001", "Description":"best trade ever"}`,
					Status: pgtype.Present,
				},
			},

			expectedStatus: http.StatusOK,
			expectedResults: &RetrieveResponse{
				CRN: "000111222",
				PrimaryTrade: &primaryTrade{
					Code:        "00001",
					Description: "best trade ever",
				},
			},
		},
		{
			name:   "primary trade",
			auth:   &common.AuthData{PartnerID: "test"},
			crn:    "000111222",
			groups: []string{},

			stgErr: nil,
			stgResults: &storage.Data{
				CRN: pgtype.Text{
					String: "000111222",
					Status: pgtype.Present,
				},
				PrimaryTrade: pgtype.Text{
					String: `{"Code": "00001", "Description":"best trade ever"}`,
					Status: pgtype.Present,
				},
			},

			expectedStatus: http.StatusOK,
			expectedResults: &RetrieveResponse{
				CRN: "000111222",
				PrimaryTrade: &primaryTrade{
					Code:        "00001",
					Description: "best trade ever",
				},
			},
		},
		{
			name:   "broken primary trade",
			auth:   &common.AuthData{PartnerID: "test"},
			crn:    "000111222",
			groups: []string{},

			stgErr: nil,
			stgResults: &storage.Data{
				CRN: pgtype.Text{
					String: "000111222",
					Status: pgtype.Present,
				},
				PrimaryTrade: pgtype.Text{
					String: `{"xxxx": "00001", "yyyy":"best trade ever"}`,
					Status: pgtype.Present,
				},
			},

			expectedStatus: http.StatusOK,
			expectedResults: &RetrieveResponse{
				CRN: "000111222",
			},
		},
		{
			name:   "with dnd",
			auth:   &common.AuthData{PartnerID: "test"},
			crn:    "000111222",
			groups: []string{"dnb"},

			stgErr: nil,
			stgResults: &storage.Data{
				CRN: pgtype.Text{
					String: "000111222",
					Status: pgtype.Present,
				},
				PrimaryTrade: pgtype.Text{
					String: `{"xxxx": "00001", "yyyy":"best trade ever"}`,
					Status: pgtype.Present,
				},
				DnBBlueCollarEmployees: pgtype.Float8{Float: 1, Status: pgtype.Present},
				DnBEmployees:           pgtype.Float8{Float: 1, Status: pgtype.Present},
			},

			expectedStatus: http.StatusOK,
			expectedResults: &RetrieveResponse{
				CRN: "000111222",
				DnB: &DnB{
					BlueCollarEmployees:    1,
					Employees:              1,
					DelinquencyScore:       "",
					DunsNumber:             "",
					EstimateNetWorth:       0,
					EstimateSales:          0,
					EstimateWorkingCapital: 0,
					FailureScore:           0,
					MaxCredit:              0,
					RiskIndicator:          "",
					SicCode:                "",
					WageEstimate:           0,
					WhiteCollarEmployees:   0,
				},
			},
		},
		{
			name:           "invalid groups",
			auth:           &common.AuthData{PartnerID: "test"},
			stgErr:         storage.ErrInvalidGroups,
			crn:            "000111222",
			groups:         []string{"xxx"},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "storage error",
			auth:           &common.AuthData{PartnerID: "test"},
			stgErr:         errors.New("oops"),
			crn:            "000111222",
			groups:         []string{},
			expectedStatus: http.StatusInternalServerError,
		},
		{
			name:           "not found",
			auth:           &common.AuthData{PartnerID: "test"},
			stgErr:         storage.ErrNotFound,
			crn:            "000111222",
			groups:         []string{},
			expectedStatus: http.StatusNotFound,
		},
	}

	for i := range tests {
		tt := tests[i]
		t.Run(tt.name, func(t *testing.T) {
			stg := &mock.StorageMock{
				Err:     tt.stgErr,
				Results: tt.stgResults,
			}
			h := New(stg)
			router := mux.NewRouter()
			endpoint := fmt.Sprintf("/v2/company/%s", tt.crn)
			router.HandleFunc(endpoint, server.ToHTTPHandlerFunc(h.Retrieve))
			u, err := url.Parse(endpoint)
			assert.Nil(t, err, "unexpected error")

			if len(tt.groups) > 0 {
				values := url.Values{}
				groups := strings.Join(tt.groups, ",")
				values.Add("groups", groups)
				u.RawQuery = values.Encode()
			}
			req := httptest.NewRequest(http.MethodGet, u.String(), nil)
			req = req.WithContext(common.SetAuthData(req.Context(), tt.auth))
			rr := httptest.NewRecorder()
			router.ServeHTTP(rr, req)
			assert.Equal(t, tt.expectedStatus, rr.Code, "unexpected status code")
			if tt.expectedStatus == http.StatusOK {
				data, err := ioutil.ReadAll(rr.Body)
				assert.Nil(t, err, "unexpected error reading response payload")
				resp := &RetrieveResponse{}
				err = json.Unmarshal(data, resp)
				assert.Nil(t, err, "unexpected error unmarshaling json data")
				assert.Equal(t, tt.expectedResults, resp, "unexpected results")
			}
		})
	}
}
