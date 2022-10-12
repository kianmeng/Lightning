defmodule Lightning.Repo.Migrations.MoveJobRunRelations do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      add :job_id, references(:jobs, on_delete: :delete_all, type: :binary_id), null: false
    end

    execute(&update_runs/0, fn -> nil end)
  end

  defp update_runs() do
    repo().query!(
      """
      UPDATE runs
      SET project_id=subquery.project_id,
          job_id=subquery.job_id
      FROM (
        SELECT r.id,
               e.project_id,
               e.job_id
        FROM runs r
        LEFT JOIN invocation_events e ON r.event_id = e.id
      ) AS subquery
      WHERE runs.id = subquery.id;
      """,
      [],
      log: :info
    )
  end
end
