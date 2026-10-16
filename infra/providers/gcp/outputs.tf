# Same logical interface as infra/providers/aws/outputs.tf.
output "cluster_name" { value = { for k, c in google_container_cluster.this : k => c.name } }
output "cluster_endpoint" {
  value     = { for k, c in google_container_cluster.this : k => c.endpoint }
  sensitive = true
}
output "workload_identity_provider" { value = "${var.project_id}.svc.id.goog" }
output "postgres_endpoint" { value = google_sql_database_instance.primary.private_ip_address }
output "postgres_replica_endpoint" { value = google_sql_database_instance.replica.private_ip_address }
output "redis_endpoint" { value = { for k, r in google_redis_instance.this : k => r.host } }
output "app_secrets" { value = google_secret_manager_secret.app.secret_id }
output "image_repository" {
  value = "us-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}
