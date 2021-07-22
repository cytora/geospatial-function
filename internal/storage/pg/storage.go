package pg

import (
	"context"
	"errors"
	"io"
	"net/url"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds/rdsutils"
	backoff "github.com/cenkalti/backoff/v4"
	"github.com/georgysavva/scany/pgxscan"
	"github.com/jackc/pgx/v4/pgxpool"

	"github.com/cytora/geospatial-lambda/internal/config"
	"github.com/cytora/geospatial-lambda/internal/storage"
	"github.com/cytora/go-platform-utils/logging"
)

type Storage struct {
	pool *pgxpool.Pool
	conf *config.Config
}

func connect(conf *config.Config) (*pgxpool.Pool, error) {
	ats := time.Now()
	sess := session.Must(session.NewSession(&aws.Config{
		Region: aws.String(conf.AWSRegion),
	}))
	token, err := rdsutils.BuildAuthToken(conf.RDSProxyEndpoint, conf.AWSRegion, conf.RDSProxyUser, sess.Config.Credentials)
	if err != nil {
		logging.FatalNoCtx(err, logging.Data{"version": conf.Version}, "failed to retrieve token")
	}
	psqlUrl, err := url.Parse("postgres://")
	if err != nil {
		logging.FatalNoCtx(err, logging.Data{"version": conf.Version}, "failed to parse url")
	}
	psqlUrl.Host = conf.RDSProxyEndpoint
	psqlUrl.User = url.UserPassword(conf.RDSProxyUser, token)
	psqlUrl.Path = conf.RDSDBName
	q := psqlUrl.Query()
	q.Add("sslmode", "require")
	psqlUrl.RawQuery = q.Encode()
	cts := time.Now()
	pool, err := pgxpool.Connect(context.Background(), psqlUrl.String())
	if err != nil {
		return nil, err
	}
	logging.Info(context.Background(), logging.Data{"proxy": conf.RDSProxyEndpoint, "connection_time": time.Since(cts), "auth_time": time.Since(ats)}, "connection stats")
	return pool, nil
}

func New(conf *config.Config) (*Storage, error) {
	pool, err := connect(conf)
	return &Storage{
		conf: conf,
		pool: pool,
	}, err
}

func (s *Storage) reconnect(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := s.pool.Ping(ctx); err == nil {
		return nil
	}
	logging.Info(ctx, nil, "reconnecting")
	pool, err := connect(s.conf)
	if err != nil {
		return err
	}
	s.pool = pool
	return nil
}

func (s *Storage) CompanyData(ctx context.Context, crn string, groups []string) (*storage.Data, error) {
	if !validateGroups(groups) {
		return nil, storage.ErrInvalidGroups
	}
	groups = append(groups, baseGroup)
	query := generateQuery(groups)
	ts := time.Now()
	data := &storage.Data{}

	bo := backoff.NewExponentialBackOff()
	bo.InitialInterval = 50 * time.Millisecond
	bo.MaxElapsedTime = 10 * time.Second
	ticker := backoff.NewTicker(bo)
	var err error
	for range ticker.C {
		if err = pgxscan.Get(ctx, s.pool, data, query, crn); err != nil {
			logging.Error(ctx, err, nil, "query error")
			switch {
			case pgxscan.NotFound(err):
				return nil, storage.ErrNotFound
			case errors.Is(err, io.ErrUnexpectedEOF):
				if err := s.reconnect(ctx); err != nil {
					logging.Error(ctx, err, nil, "failed to reconnect")
				}
			default:
				return nil, storage.ErrStorage
			}
		} else {
			ticker.Stop()
		}
	}
	if err != nil {
		return nil, storage.ErrStorage
	}
	logging.Info(ctx, logging.Data{"crn": crn, "groups": groups, "query_time": time.Since(ts)}, "query stats")
	return data, nil
}
