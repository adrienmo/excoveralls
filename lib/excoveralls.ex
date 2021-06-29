defmodule ExCoveralls do
  @moduledoc """
  Provides the entry point for coverage calculation and output.
  This module method is called by Mix.Tasks.Test
  """
  alias ExCoveralls.Stats
  alias ExCoveralls.Cover
  alias ExCoveralls.ConfServer
  alias ExCoveralls.StatServer
  alias ExCoveralls.Travis
  alias ExCoveralls.Github
  alias ExCoveralls.Circle
  alias ExCoveralls.Semaphore
  alias ExCoveralls.Drone
  alias ExCoveralls.Local
  alias ExCoveralls.Html
  alias ExCoveralls.Json
  alias ExCoveralls.Post
  alias ExCoveralls.Xml

  @type_travis      "travis"
  @type_github      "github"
  @type_circle      "circle"
  @type_semaphore   "semaphore"
  @type_drone       "drone"
  @type_local       "local"
  @type_html        "html"
  @type_json        "json"
  @type_post        "post"
  @type_xml         "xml"

  @doc """
  This method will be called from mix to trigger coverage analysis.
  """
  def start(compile_path, _opts) do
    options = ConfServer.get()

    compile_paths = if options[:poncho] do
      base_compile_path = Path.expand(compile_path <> "../../..")
      Mix.Dep.cached() 
      |> Enum.filter(& is_nil(&1.opts[:lock])) 
      |> Enum.reject(&(&1.app in [:nex_protocol, :matching_engine]))
      |> Enum.map(& "#{base_compile_path}/#{&1.app}/ebin")
      |> Kernel.++([compile_path])
    else
      List.wrap(compile_path)
    end

    Cover.compile(compile_paths)
    fn() -> execute(options, compile_paths) end
  end

  def execute(options, compile_path) do
    stats = Cover.modules() 
    |> Stats.report() 
    |> Enum.map(&Enum.into(&1, %{}))

    stats = if options[:poncho] do
      Enum.map(stats, fn %{name: name} = stat ->
        poncho_base_folder = System.get_env("PONCHO_BASE_FOLDER", "")
        trimmed = Path.relative_to(name, poncho_base_folder)
        %{stat | name: trimmed}
      end)
    else
      stats
    end

    if options[:umbrella] do
      store_stats(stats, options, compile_path)
    else
      analyze(stats, options[:type] || "local", options)
    end
  end

  defp store_stats(stats, options, compile_paths) when is_list(compile_paths) do
    Enum.each(compile_paths, fn(compile_path) ->
      store_stats(stats, options, compile_path)
    end)
  end
  defp store_stats(stats, options, compile_path) when is_binary(compile_path) do
    {sub_app_name, _sub_app_path} =
      ExCoveralls.SubApps.find(options[:sub_apps], compile_path)
    stats = Stats.append_sub_app_name(stats, sub_app_name, options[:apps_path])
    Enum.each(stats, fn(stat) -> StatServer.add(stat) end)
  end

  @doc """
  Logic for posting from travis-ci server
  """
  def analyze(stats, @type_travis, options) do
    Travis.execute(stats, options)
  end

  @doc """
  Logic for posting from github action
  """
  def analyze(stats, @type_github, options) do
    Github.execute(stats, options)
  end

  @doc """
  Logic for posting from circle-ci server
  """
  def analyze(stats, @type_circle, options) do
    Circle.execute(stats, options)
  end

  @doc """
  Logic for posting from semaphore-ci server
  """
  def analyze(stats, @type_semaphore, options) do
    Semaphore.execute(stats, options)
  end

  @doc """
  Logic for posting from drone-ci server
  """
  def analyze(stats, @type_drone, options) do
    Drone.execute(stats, options)
  end

  @doc """
  Logic for local stats display, without posting server
  """
  def analyze(stats, @type_local, options) do
    Local.execute(stats, options)
  end

  @doc """
  Logic for html stats display, without posting server
  """
  def analyze(stats, @type_html, options) do
    Html.execute(stats, options)
  end

  @doc """
  Logic for JSON output, without posting server
  """
  def analyze(stats, @type_json, options) do
    Json.execute(stats, options)
  end

  @doc """
  Logic for XML output, without posting server
  """
  def analyze(stats, @type_xml, options) do
    Xml.execute(stats, options)
  end

  @doc """
  Logic for posting from general CI server with token.
  """
  def analyze(stats, @type_post, options) do
    Post.execute(stats, options)
  end

  def analyze(_stats, type, _options) do
    raise "Undefined type (#{type}) is specified for ExCoveralls"
  end
end
