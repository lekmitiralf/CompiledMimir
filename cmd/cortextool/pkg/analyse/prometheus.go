package analyse

type MetricsInPrometheus struct {
	TotalActiveSeries      int `json:"total_active_series"`
	InUseActiveSeries      int `json:"in_use_active_series"`
	AdditionalActiveSeries int `json:"additional_active_series"`

	InUseMetricCounts      []MetricCount `json:"in_use_metric_counts"`
	AdditionalMetricCounts []MetricCount `json:"additional_metric_counts"`
}

type MetricCount struct {
	Metric    string     `json:"metric"`
	Count     int        `json:"count"`
	JobCounts []JobCount `json:"job_counts"`
}

type JobCount struct {
	Job   string `json:"job"`
	Count int    `json:"count"`
}
