{
  local container = $.core.v1.container,
  local deployment = $.apps.v1.deployment,
  local service = $.core.v1.service,

  // Utils.
  local gossipLabel = $.apps.v1.statefulSet.spec.template.metadata.withLabelsMixin({ [$._config.gossip_member_label]: 'true' }),
  local byContainerPort = function(x) x.containerPort,

  //
  // Read component.
  //

  mimir_read_args::
    // The ruler remote evaluation (running in mimir-backend) connects to mimir-read via gRPC.
    $._config.grpcIngressConfig +
    $.querier_args +
    // Query-frontend configuration takes precedence over querier configuration (e.g. HTTP / gRPC settings) because
    // the query-frontend is the ingress service.
    $.query_frontend_args {
      target: 'read',
      // Restrict number of active query-schedulers.
      'query-scheduler.max-used-instances': 2,
    },

  mimir_read_ports::
    std.uniq(
      std.sort(
        $.querier_ports +
        $.ruler_ports,
        byContainerPort
      ), byContainerPort
    ),

  mimir_read_env_map:: $.querier_env_map {
    // Do not inherit GOMAXPROCS from querier because mimir-read runs more components.
    GOMAXPROCS: null,
  },

  mimir_read_node_affinity_matchers:: [],

  mimir_read_container:: if !$._config.is_read_write_deployment_mode then null else
    container.new('mimir-read', $._images.mimir_read) +
    container.withPorts($.mimir_read_ports) +
    container.withArgsMixin($.util.mapToFlags($.mimir_read_args)) +
    $.tracing_env_mixin +
    $.util.readinessProbe +
    (if std.length($.mimir_read_env_map) > 0 then container.withEnvMap(std.prune($.mimir_read_env_map)) else {}) +
    $.util.resourcesRequests('1', '12Gi') +
    $.util.resourcesLimits(null, '24Gi'),

  mimir_read_deployment: if !$._config.is_read_write_deployment_mode then null else
    deployment.new('mimir-read', $._config.mimir_read_replicas, [$.mimir_read_container]) +
    $.newMimirNodeAffinityMatchers($.mimir_read_node_affinity_matchers) +
    $.mimirVolumeMounts +
    $.newMimirSpreadTopology('mimir-read', $._config.mimir_read_topology_spread_max_skew) +
    (if !std.isObject($._config.node_selector) then {} else deployment.mixin.spec.template.spec.withNodeSelectorMixin($._config.node_selector)) +
    deployment.mixin.spec.strategy.rollingUpdate.withMaxSurge('15%') +
    deployment.mixin.spec.strategy.rollingUpdate.withMaxUnavailable(0) +
    (if $._config.memberlist_ring_enabled then gossipLabel else {}) +

    // Inherit the terminationGracePeriodSeconds from query-frontend.
    (
      local qf = $.newQueryFrontendDeployment('query-frontend', $.query_frontend_container);
      deployment.mixin.spec.template.spec.withTerminationGracePeriodSeconds(qf.spec.template.spec.terminationGracePeriodSeconds)
    ),

  mimir_read_service: if !$._config.is_read_write_deployment_mode then null else
    $.util.serviceFor($.mimir_read_deployment, $._config.service_ignored_labels),

  mimir_read_headless_service: if !$._config.is_read_write_deployment_mode then null else
    $.util.serviceFor($.mimir_read_deployment, $._config.service_ignored_labels) +
    service.mixin.metadata.withName('mimir-read-headless') +

    // Must be an headless to ensure any gRPC client using it (ruler remote evaluations)
    // correctly balances requests across all mimir-read pods.
    service.mixin.spec.withClusterIp('None'),

  mimir_read_pdb: if !$._config.is_read_write_deployment_mode then null else
    $.newMimirPdb('mimir-read'),
}
