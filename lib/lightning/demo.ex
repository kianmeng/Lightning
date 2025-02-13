defmodule Lightning.Demo do
  @moduledoc """
  Demo encapsulates logic for setting up initial data for the demo site
  """

  alias Lightning.{Projects, Accounts, Jobs, Workflows, Repo}

  import Ecto.Query

  @spec setup(nil | maybe_improper_list | map) :: %{
          jobs: [...],
          projects: [atom | %{:id => any, optional(any) => any}, ...],
          users: [atom | %{:id => any, optional(any) => any}, ...],
          workflows: [atom | %{:id => any, optional(any) => any}, ...]
        }
  @doc """
  Creates initial data and returns the created records.
  """
  def setup(opts \\ [create_super: false]) do
    {:ok, super_user} =
      if opts[:create_super] do
        Accounts.register_superuser(%{
          first_name: "Sizwe",
          last_name: "Super",
          email: "super@openfn.org",
          password: "welcome123"
        })
      else
        {:ok, nil}
      end

    {:ok, admin} =
      Accounts.register_user(%{
        first_name: "Amy",
        last_name: "Admin",
        email: "demo@openfn.org",
        password: "welcome123"
      })

    {:ok, editor} =
      Accounts.register_user(%{
        first_name: "Esther",
        last_name: "Editor",
        email: "editor@openfn.org",
        password: "welcome123"
      })

    {:ok, viewer} =
      Accounts.register_user(%{
        first_name: "Vikram",
        last_name: "Viewer",
        email: "viewer@openfn.org",
        password: "welcome123"
      })

    {:ok, openhie_project} =
      Projects.create_project(%{
        name: "openhie-project",
        project_users: [
          %{user_id: admin.id, role: :admin},
          %{user_id: editor.id, role: :editor},
          %{user_id: viewer.id, role: :viewer}
        ]
      })

    {:ok, dhis2_project} =
      Projects.create_project(%{
        name: "dhis2-project",
        project_users: [
          %{user_id: admin.id, role: :admin}
        ]
      })

    {:ok, openhie_workflow} =
      Workflows.create_workflow(%{
        name: "OpenHIE Workflow",
        project_id: openhie_project.id
      })

    {:ok, fhir_standard_data} =
      Jobs.create_job(%{
        name: "Transform data to FHIR standard",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http",
        trigger: %{type: "webhook"},
        workflow_id: openhie_workflow.id
      })

    {:ok, send_to_openhim} =
      Jobs.create_job(%{
        name: "Send to OpenHIM to route to SHR",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http",
        trigger: %{
          type: "on_job_success",
          upstream_job_id: fhir_standard_data.id
        },
        workflow_id: openhie_workflow.id
      })

    {:ok, notify_upload_successful} =
      Jobs.create_job(%{
        name: "Notify CHW upload successful",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_success", upstream_job_id: send_to_openhim.id},
        workflow_id: openhie_workflow.id
      })

    {:ok, notify_upload_failed} =
      Jobs.create_job(%{
        name: "Notify CHW upload failed",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_failure", upstream_job_id: send_to_openhim.id},
        workflow_id: openhie_workflow.id
      })

    {:ok, dhis2_workflow} =
      Workflows.create_workflow(%{
        name: "DHIS2 to Sheets",
        project_id: dhis2_project.id
      })

    {:ok, get_dhis2_data} =
      Jobs.create_job(%{
        name: "Get DHIS2 data",
        body: "fn(state => state);",
        adaptor: "@openfn/language-dhis2",
        trigger: %{type: "cron", cron_expression: "0 * * * *"},
        workflow_id: dhis2_workflow.id
      })

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(%{
        name: "Upload to Google Sheet",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_success", upstream_job_id: get_dhis2_data.id},
        workflow_id: dhis2_workflow.id
      })

    %{
      users: [super_user, admin, editor, viewer],
      projects: [openhie_project, dhis2_project],
      workflows: [openhie_workflow, dhis2_workflow],
      jobs: [
        fhir_standard_data,
        send_to_openhim,
        notify_upload_successful,
        notify_upload_failed,
        get_dhis2_data,
        upload_to_google_sheet
      ]
    }
  end

  def tear_down(opts \\ [destroy_super: false]) do
    delete_all_entities([
      Lightning.Attempt,
      Lightning.AttemptRun,
      Lightning.AuthProviders.AuthConfig,
      Lightning.Credentials.Audit,
      Lightning.Projects.ProjectCredential,
      Lightning.Credentials.Credential,
      Lightning.WorkOrder,
      Lightning.InvocationReason,
      Lightning.Invocation.Dataclip,
      Lightning.Invocation.Run,
      Lightning.Jobs.Job,
      Lightning.Jobs.Trigger,
      Lightning.Projects.ProjectUser,
      Lightning.Projects.Project,
      Lightning.Workflows.Workflow
    ])

    delete_other_tables(["oban_jobs", "oban_peers"])

    if opts[:destroy_super] do
      Repo.delete_all(Lightning.Accounts.User)
    else
      from(u in Lightning.Accounts.User, where: u.role != :superuser)
      |> Repo.all()
      |> Enum.each(fn user -> Lightning.Accounts.delete_user(user) end)
    end
  end

  defp delete_all_entities(entities),
    do: Enum.each(entities, fn entity -> Repo.delete_all(entity) end)

  defp delete_other_tables(tables_names) do
    Enum.each(tables_names, fn name ->
      Ecto.Adapters.SQL.query!(Repo, "DELETE FROM #{name}")
    end)
  end
end
