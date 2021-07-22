package v2

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/cytora/geospatial-lambda/internal"
	"github.com/cytora/geospatial-lambda/internal/handler"
	"github.com/cytora/go-platform-utils/client"
	"github.com/cytora/go-platform-utils/common"
)

type GeospatialLambda interface {
	RetreiveIntersectedLatLon()
}

type CompanyService interface {
	RetrieveCompanyData(ctx context.Context, crn string, groups []string) (*handler.RetrieveResponse, error)
}

type Client struct {
	c *client.HTTPClient
}

func New(opts ...client.HTTPClientFunc) (CompanyService, error) {
	errorCodeLookup := common.NewErrorCodeLookup(internal.ServiceName)
	c, err := client.NewClient(internal.ServiceName, errorCodeLookup, opts...)
	if err != nil {
		return nil, err
	}
	return &Client{
		c: c,
	}, nil
}

func (s *Client) RetrieveCompanyData(ctx context.Context, crn string, groups []string) (*handler.RetrieveResponse, error) {
	params := url.Values{
		"groups": {strings.Join(groups, ",")},
	}
	res := handler.RetrieveResponse{}
	err := s.c.Send(ctx, client.HTTPRequest{
		API:           internal.CompanyDataEndpoint,
		Method:        http.MethodGet,
		Path:          fmt.Sprintf("/v1/company/%s", crn),
		QueryParams:   params,
		NotLogReqBody: true,
		NotLogResBody: true,
	}, &res)
	return &res, err
}
