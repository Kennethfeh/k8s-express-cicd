const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Kubernetes-specific health checks
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || '3.0.0',
    hostname: require('os').hostname(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    environment: process.env.NODE_ENV || 'production',
    project: 'DevOps Kubernetes',
    kubernetes: {
      namespace: process.env.KUBERNETES_NAMESPACE || 'default',
      pod_name: process.env.HOSTNAME || require('os').hostname(),
      service_account: process.env.KUBERNETES_SERVICE_ACCOUNT || 'default'
    }
  });
});

// Kubernetes readiness probe
app.get('/ready', (req, res) => {
  // Simulate readiness check
  const isReady = process.uptime() > 10; // Ready after 10 seconds
  
  if (isReady) {
    res.status(200).json({
      status: 'ready',
      timestamp: new Date().toISOString(),
      uptime: process.uptime()
    });
  } else {
    res.status(503).json({
      status: 'not_ready',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      message: 'Application is starting up'
    });
  }
});

// Kubernetes liveness probe
app.get('/live', (req, res) => {
  // Simulate liveness check
  res.status(200).json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    pid: process.pid,
    uptime: process.uptime()
  });
});

// Main endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from DevOps Project 3 - Kubernetes!',
    hostname: require('os').hostname(),
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || '3.0.0',
    project: 'DevOps Kubernetes',
    features: [
      'EKS cluster deployment',
      'Kubernetes pods and services',
      'Helm package management',
      'Horizontal Pod Autoscaling',
      'Ingress controller',
      'Rolling deployments'
    ],
    kubernetes_info: {
      namespace: process.env.KUBERNETES_NAMESPACE || 'default',
      pod_name: process.env.HOSTNAME || require('os').hostname(),
      node_name: process.env.KUBERNETES_NODE_NAME || 'unknown',
      cluster: 'devops-project-3'
    }
  });
});

// Load testing endpoint
app.get('/load/:intensity?', (req, res) => {
  const intensity = parseInt(req.params.intensity) || 1;
  const iterations = intensity * 10000;
  
  // CPU intensive task to test auto-scaling
  let result = 0;
  const start = Date.now();
  
  for (let i = 0; i < iterations; i++) {
    result += Math.sqrt(i);
  }
  
  const duration = Date.now() - start;
  
  res.json({
    message: 'Load test completed',
    intensity: intensity,
    iterations: iterations,
    duration_ms: duration,
    result: result.toString().substring(0, 10),
    hostname: require('os').hostname(),
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint (basic Prometheus-style metrics)
app.get('/metrics', (req, res) => {
  const metrics = `
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/"} ${Math.floor(Math.random() * 1000)}
http_requests_total{method="GET",endpoint="/health"} ${Math.floor(Math.random() * 100)}

# HELP process_uptime_seconds Process uptime in seconds
# TYPE process_uptime_seconds gauge  
process_uptime_seconds ${process.uptime()}

# HELP nodejs_memory_usage_bytes Node.js memory usage
# TYPE nodejs_memory_usage_bytes gauge
nodejs_memory_usage_bytes{type="rss"} ${process.memoryUsage().rss}
nodejs_memory_usage_bytes{type="heapUsed"} ${process.memoryUsage().heapUsed}
nodejs_memory_usage_bytes{type="heapTotal"} ${process.memoryUsage().heapTotal}
`.trim();

  res.set('Content-Type', 'text/plain');
  res.send(metrics);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
});

// Start server
app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 DevOps Project 3 - Kubernetes server running on port ${port}`);
  console.log(`📱 Health: http://localhost:${port}/health`);
  console.log(`✅ Ready: http://localhost:${port}/ready`);
  console.log(`💓 Live: http://localhost:${port}/live`);
  console.log(`📊 Metrics: http://localhost:${port}/metrics`);
  console.log(`⚡ Load test: http://localhost:${port}/load/5`);
  console.log(`🌐 Main: http://localhost:${port}`);
});

