-- +goose Up
-- +goose StatementBegin

DELETE FROM cron.job WHERE jobname IN (
    'cron_grafana',
    'cron_windy',
    'refresh_log_mat_view'
);

-- +goose StatementEnd