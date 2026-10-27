"""Distributed tracing with OpenTelemetry, exported over OTLP/HTTP to SigNoz.

Off unless OTEL_EXPORTER_OTLP_ENDPOINT is set, so tests, manage.py and
docker-compose run without a collector. Everything else (service name,
resource attributes, excluded URLs) comes from the standard OTEL_* env vars.

Called from wsgi.py, which gunicorn imports in each worker after forking
(no --preload): the span exporter's background thread has to be started in
the process that produces the spans.
"""

import os


def configure_tracing():
    if not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return

    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.django import DjangoInstrumentor
    from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    provider = TracerProvider(resource=Resource.create())
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    DjangoInstrumentor().instrument()
    # psycopg2-binary installs the same `psycopg2` module under a different
    # distribution name, which the instrumentor's version check doesn't know.
    Psycopg2Instrumentor().instrument(skip_dep_check=True)
