defmodule Adept.Repo.Migrations.AddReferenceAnswerToTestCases do
  use Ecto.Migration

  def change do
    alter table(:arcana_evaluation_test_cases) do
      add(:reference_answer, :text)
    end
  end
end
