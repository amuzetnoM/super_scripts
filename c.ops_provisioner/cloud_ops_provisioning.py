import argparse
import collections
import concurrent.futures
import csv
import dataclasses
import datetime
import enum
import json
import logging
import os
import re
import subprocess
import sys
import time
from typing import Any, Dict, Iterable, List, Tuple


_logger = logging.getLogger(__name__)


def _popen(*args, **kwargs):
  """Wrapper around subprocess.Popen to make testing easier (patch target)."""
  return subprocess.Popen(*args, **kwargs)


# Built-in providers so this file can be used standalone as a single, portable
# script. Providers are pluggable but included here to keep one-file usage
# simple.


class _LocalGcloudProvider:
  """Executes `gcloud compute ssh` using the local gcloud binary."""
  def start_process(self, instance_info, command_str: str, log_file: str) -> Any:
    # Build the argv list for gcloud matching earlier logic.
    ssh_command = [
        "gcloud",
        "compute",
        "ssh",
        instance_info.instance,
        "--project",
        instance_info.project,
        "--zone",
        instance_info.zone,
        "--quiet",
        "--strict-host-key-checking=no",
        "--ssh-flag",
        "-o ConnectTimeout=20",
        "--command",
        command_str,
    ]
    return _popen(args=ssh_command, shell=False, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)


class _MockProvider:
  """A provider used for `--dry-run` that simulates success without network calls."""

  class _Proc:
    def __init__(self):
      self.returncode = 0

    def wait(self):
      return 0

    def communicate(self, timeout=None):
      return (b"[mock] simulated output", None)

  def start_process(self, instance_info, command_str: str, log_file: str) -> Any:
    return self._Proc()


class _ParamikoProvider:
  """SSH provider using Paramiko for environments without gcloud.

  This provider expects that the instance hostname/IP is reachable via SSH.
  You can pass `--ssh-user` and `--ssh-key` flags to control auth.
  """

  def __init__(self, ssh_user: str = None, ssh_key: str = None):
    self.ssh_user = ssh_user
    self.ssh_key = ssh_key

  def start_process(self, instance_info, command_str: str, log_file: str) -> Any:
    try:
      import paramiko
    except Exception as e:
      raise RuntimeError(
          "Paramiko provider requires 'paramiko' package. Install with: pip install paramiko"
      ) from e

    hostname = instance_info.instance
    username = self.ssh_user
    key_filename = self.ssh_key

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    connect_kwargs = {}
    if username:
      connect_kwargs['username'] = username
    if key_filename:
      connect_kwargs['key_filename'] = key_filename

    # Execute the remote command synchronously and return a process-like object
    stdin, stdout, stderr = None, None, None
    try:
      client.connect(hostname, **connect_kwargs)
      stdin, stdout, stderr = client.exec_command(command_str)
      out = stdout.read() or b""
      err = stderr.read() or b""
      exit_status = stdout.channel.recv_exit_status()
    finally:
      try:
        client.close()
      except Exception:
        pass

    class _Proc:
      def __init__(self, returncode, output):
        self.returncode = returncode

      def wait(self):
        return exit_status

      def communicate(self, timeout=None):
        return (out, err)

    return _Proc(exit_status, out)


class EntriesValidationError(Exception):
  """Base exception for entries validation exception."""


class InstanceFullNameInvalidError(Exception):
  """Base exception for instance full name is invalid."""


class InstanceEntriesDuplicateError(Exception):
  """Base exception for instance full name appears in more than one entry."""


class AgentRuleParseError(Exception):
  """Base exception for agent rule cannot be parsed."""


class AgentRuleInvalidError(Exception):
  """Base exception for agent rule is invalid."""


class SSHCommandError(Exception):
  """Raised when an SSH command fails to execute."""
  pass


class AgentType(str, enum.Enum):
  LOGGING = "logging"
  METRICS = "metrics"
  OPS_AGENT = "ops-agent"


class ProvisioningStatus(str, enum.Enum):
  PENDING = "PENDING"
  RUNNING = "RUNNING"
  SUCCESS = "SUCCESS"
  FAILURE = "FAILURE"
  SKIPPED = "SKIPPED"


@dataclasses.dataclass(frozen=True)
class InstanceInfo:
  """InstanceInfo contains instance related information.

  Attributes:
    project: str, project name.
    zone: str, zone name.
    instance: str, instance name.
  """
  project: str
  zone: str
  instance: str

  def __str__(self) -> str:
    return f"projects/{self.project}/zones/{self.zone}/instances/{self.instance}"

  def AsFilename(self) -> str:
    return f"{self.project}_{self.zone}_{self.instance}"


@dataclasses.dataclass(frozen=True)
class AgentDetail:
  name: str
  repo_script: str
  start_agent_script: str
  additional_install_flags: str


_AGENT_DETAILS = {
    AgentType.LOGGING:
        AgentDetail(
            name="google-fluentd",
            repo_script="add-logging-agent-repo.sh",
            start_agent_script="sudo service google-fluentd start",
            additional_install_flags=""),
    AgentType.METRICS:
        AgentDetail(
            name="stackdriver-agent",
            repo_script="add-monitoring-agent-repo.sh",
            start_agent_script="sudo service stackdriver-agent start",
            additional_install_flags=""),
    AgentType.OPS_AGENT:
        AgentDetail(
            name="google-cloud-ops-agent",
            repo_script="add-google-cloud-ops-agent-repo.sh",
            # The Ops Agent starts the services automatically.
            # The colon (:) is the bash no-op operator.
            start_agent_script=":",
            additional_install_flags=
            "--uninstall-standalone-logging-agent --uninstall-standalone-monitoring-agent"
        ),
}

_AGENT_VERSION_LATEST = "latest"
_PINNED_MAJOR_VERSION_RE = re.compile(r"^\d+\.\*\.\*$")
_PINNED_VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
_INSTALL_COMMAND = (
    "curl -sSO https://dl.google.com/cloudagents/{script_name}; "
    "sudo bash {script_name} --also-install {install_version} "
    "{additional_flags}; "
    "{start_agent}; "
    "for i in {{1..3}}; do if (ps aux | grep 'opt[/].*{agent}.*bin/'); "
    "then echo '{agent} runs successfully.'; break; fi; sleep 1s; done")


class ProvisioningTask:
  """A task to provision one instance."""

  @dataclasses.dataclass
  class ProcessInfo:
    process: Any
    log_file: str
    out_content: str = None

  def __init__(self,
               instance_info: InstanceInfo,
               agent_rules: List[Dict[str, str]],
               log_dir: str,
               max_retries: int,
               status: ProvisioningStatus = ProvisioningStatus.PENDING,
               provider: Any = None):
    self.instance_info = instance_info
    self.agent_rules = agent_rules
    self.log_dir = log_dir
    self.max_retries = max_retries
    self.status = status
    self.process_info = None
    self.agents_status = {}
    self.provider = provider

  @property
  def agent_types(self) -> List[str]:
    return [rule["type"] for rule in self.agent_rules]

  def _start_process(self) -> "ProvisioningTask.ProcessInfo":
    """Starts a process to execute commands on a VM instance.

    This method constructs the necessary shell commands to install Google Cloud
    Ops agents based on the agent rules. It then uses `gcloud compute ssh` to
    execute these commands on the target VM. The method includes a retry
    mechanism with exponential backoff to handle transient network issues.

    Returns:
      A ProcessInfo object containing the subprocess information and log file path.

    Raises:
      SSHCommandError: If the SSH command fails after the maximum number of retries.
    """
    commands = []
    commands.append('echo "$(date -Ins) Starting running commands."')
    for agent_rule in self.agent_rules:
      agent_details = _AGENT_DETAILS[agent_rule["type"]]
      command = _INSTALL_COMMAND.format(
          script_name=agent_details.repo_script,
          install_version=(f"--version={agent_rule['version']}"
                           if "version" in agent_rule else ""),
          start_agent=agent_details.start_agent_script,
          additional_flags=agent_details.additional_install_flags,
          agent=agent_details.name)
      commands.append(command)
    commands.append('echo "$(date -Ins) Finished running commands."')
    # Build the remote command string to execute on the instance.
    command_str = ";".join(commands)
    # Build the argv list for gcloud. Prefer `shell=False` and a list to avoid
    # shell injection and brittle quoting. `gcloud compute ssh` expects the
    # remote command as a single argument following `--command`.
    ssh_command = [
      "gcloud",
      "compute",
      "ssh",
      self.instance_info.instance,
      "--project",
      self.instance_info.project,
      "--zone",
      self.instance_info.zone,
      "--quiet",
      "--strict-host-key-checking=no",
      "--ssh-flag",
      "-o ConnectTimeout=20",
      "--command",
      command_str,
    ]
    _logger.info("Instance: %s - Starting process to run command: %s.",
           self.instance_info.instance, " ".join(ssh_command))
    instance_file = os.path.join(self.log_dir,
                                 f"{self.instance_info.AsFilename()}.log")

    for i in range(self.max_retries):
      if self.provider is not None:
        process = self.provider.start_process(ssh_command, instance_file)
      else:
        process = _popen(
            args=ssh_command,
            shell=False,
            stderr=subprocess.STDOUT,
            stdout=subprocess.PIPE)
      if process.wait() == 0:
        return self.ProcessInfo(process=process, log_file=instance_file)
      _logger.warning(
          "Instance: %s - Command failed with exit code %s. Retrying in %s seconds.",
          self.instance_info.instance, process.returncode, 2**i)
      time.sleep(2**i)
    raise SSHCommandError(
        f"Instance: {self.instance_info.instance} - Command failed after "
        f"{self.max_retries} retries. See log file for more details: {instance_file}"
    )

  def run(self):
    if self.status == ProvisioningStatus.SKIPPED:
      return self
    self.status = ProvisioningStatus.RUNNING
    print(
        f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%S.%fZ} "
        f"Processing instance: {self.instance_info}.")
    try:
      self.process_info = self._start_process()
    except SSHCommandError as e:
      _logger.error("Instance: %s - %s", self.instance_info.instance, e)
      self.status = ProvisioningStatus.FAILURE
    return self

  def wait_for_completion(self):
    if self.status == ProvisioningStatus.SKIPPED:
      return
    if self.process_info:
      try:
        outs, _ = self.process_info.process.communicate(timeout=600)
      except subprocess.TimeoutExpired:
        self.process_info.process.kill()
        outs, _ = self.process_info.process.communicate()
      self.process_info.out_content = outs.decode("utf-8")
      with open(self.process_info.log_file, "w") as f:
        f.write(f"Installing {','.join(sorted(self.agent_types))}\n")
        f.write(self.process_info.out_content)
      per_agent_success = {
          t: f"\n{_AGENT_DETAILS[t].name} runs successfully.\n" in
          self.process_info.out_content for t in self.agent_types
      }

      for agent_type, agent_success in per_agent_success.items():
        self.agents_status[agent_type] = ("successfully runs"
                                          if agent_success else
                                          _Bold("fails to run"))
      if all(per_agent_success.values()):
        self.status = ProvisioningStatus.SUCCESS
      else:
        self.status = ProvisioningStatus.FAILURE


class Provisioner:
  """Manages all the provisioning tasks."""

  def __init__(self,
               vms_file: str,
               max_workers: int = 10,
               force: bool = False,
               max_retries: int = 3,
               provider: str = "local-gcloud",
               dry_run: bool = False,
               ssh_user: str = None,
               ssh_key: str = None):
    self.vms_file = vms_file
    self.log_dir = os.path.join(
        ".", "google_cloud_ops_agent_provisioning",
        f"{datetime.datetime.now(datetime.timezone.utc):%Y%m%d-%H%M%S_%f}")
    self.state_file = os.path.join(
        ".", "google_cloud_ops_agent_provisioning", "provisioning_state.json")
    self.tasks = []
    self.max_workers = max_workers
    self.force = force
    self.max_retries = max_retries
    self.state = {}
    # Prefer built-in providers for single-file portability.
    if provider == "paramiko":
      self.provider_instance = _ParamikoProvider(ssh_user=ssh_user, ssh_key=ssh_key)
    elif dry_run:
      self.provider_instance = _MockProvider()
    else:
      # default provider: local gcloud wrapper
      self.provider_instance = _LocalGcloudProvider()
    self.provider_name = provider

  def _read_state(self):
    if self.force:
      return
    try:
      with open(self.state_file, "r") as f:
        self.state = json.load(f)
    except FileNotFoundError:
      pass

  def _write_state(self):
    with open(self.state_file, "w") as f:
      json.dump(self.state, f, indent=2)

  def _read_entries_from_file(self) -> List[Tuple[str, str]]:
    """Reads row entries reading from file."""
    entries = []
    with open(self.vms_file, "r") as f:
      full_input = f.read()
      _logger.debug("Input file content:\n%s", full_input)
      entries_reader = csv.reader(full_input.split("\n"))
      for entry in entries_reader:
        if not entry:
          continue
        try:
          instance_full_name, agent_rules = entry
        except ValueError:
          raise Exception(
              f"Incorrect entry {entry}. "
              'Expected format: `"instance_full_name","agent_rules"`.')
        entries.append((instance_full_name.strip(), agent_rules.strip()))
    return entries

  def _validate_instances_duplication(self, instances: Iterable[str]) -> None:
    duplicate_instances = sorted(
        k for k, v in collections.Counter(instances).items() if v > 1)
    if duplicate_instances:
      raise InstanceEntriesDuplicateError("\n".join([
          f"Instance - {instance} has more than one record in the file. "
          "Please have at most one entry per instance."
          for instance in duplicate_instances
      ]))

  def _validate_agent_types(self,
                            agent_rules: Iterable[Dict[str, str]]) -> List[str]:
    """Validates types of agent rules."""
    agent_types = collections.Counter(r["type"] for r in agent_rules)
    errors = []
    for agent_type in agent_types:
      if agent_type not in _AGENT_DETAILS:
        errors.append(
            f"Invalid agent type: {agent_type}. "
            f"Valid types are: {', '.join(_AGENT_DETAILS.keys())}")
    duplicate_types = sorted(k for k, v in agent_types.items() if v > 1)
    errors.extend([
        f"At most one agent with type [{t}] is allowed." for t in duplicate_types
    ])
    if agent_types[AgentType.OPS_AGENT] > 0 and sum(agent_types.values()) > 1:
      errors.append(
          f"An agent with type [{AgentType.OPS_AGENT}] is detected. "
          "No other agent type is allowed. The Ops Agent has both a logging "
          "module and a metrics module already.")
    return errors

  def _validate_agent_version(self, version: str) -> List[str]:
    """Validates agent version."""
    if version == _AGENT_VERSION_LATEST:
      return []

    valid_pin_res = {
        _PINNED_MAJOR_VERSION_RE,
        _PINNED_VERSION_RE,
    }
    if any(regex.search(version) for regex in valid_pin_res):
      return []
    return [
        f"The agent version {version} is not allowed. Expected values: "
        "[latest] or anything in the format of "
        "[MAJOR_VERSION.MINOR_VERSION.PATCH_VERSION] or [MAJOR_VERSION.*.*]."
    ]

  def _extract_agent_rules(self, instance: str,
                           agent_rules: str) -> List[Dict[str, str]]:
    """Extracts agent rules from string blob."""
    try:
      decoded_rules = json.loads(agent_rules)
    except ValueError as e:
      raise AgentRuleParseError(
          f"Instance - {instance} has invalid agent_rules {agent_rules} -- {e}.")

    if not decoded_rules:
      raise AgentRuleParseError(
          f"Instance - {instance} requires at least one agent rule.")
    type_errors = []
    for agent_rule in decoded_rules:
      if "type" not in agent_rule:
        type_errors.append(
            f"Instance - {instance} has agent rules that is missing required "
            "`type` field.")
    if type_errors:
      raise AgentRuleParseError("\n".join(type_errors))
    return decoded_rules

  def _parse_and_validate_agent_rules(
      self, instance: str, agent_rules: str) -> List[Dict[str, str]]:
    """Parses and validates agent rules."""
    errors = []
    try:
      agent_rule_list = self._extract_agent_rules(instance, agent_rules)
    except AgentRuleParseError as e:
      raise AgentRuleInvalidError(str(e))
    errors.extend(self._validate_agent_types(agent_rule_list))
    for agent_rule in agent_rule_list:
      if "version" in agent_rule:
        errors.extend(self._validate_agent_version(agent_rule["version"]))
    if errors:
      raise AgentRuleInvalidError(
          f"Instance - {instance}: {' | '.join(str(error) for error in errors)}"
      )
    return agent_rule_list

  def _parse_and_validate_instance_full_name(self,
                                               instance: str) -> InstanceInfo:
    instance_details = re.match(
        r"^projects\/([\w-]+)\/zones\/([\w-]+)\/instances\/([\w-]+)$", instance)
    if not instance_details:
      raise InstanceFullNameInvalidError(
          f"Instance - {instance} has invalid instance full name")
    project, zone, instance_name = instance_details.groups()
    return InstanceInfo(project, zone, instance_name)

  def _parse_and_validate_entries(
      self, entries: List[Tuple[str, str]]
  ) -> List[Tuple[InstanceInfo, List[Dict[str, str]]]]:
    """Parses and validates entries."""
    error_msgs = []
    parsed_entries = []
    for instance_full_name, agent_rules in entries:
      instance_error_msgs = []
      try:
        parsed_instance_name = self._parse_and_validate_instance_full_name(
            instance_full_name)
      except InstanceFullNameInvalidError as e:
        instance_error_msgs.append(str(e))
      try:
        parsed_agent_rules = self._parse_and_validate_agent_rules(
            instance_full_name, agent_rules)
      except AgentRuleInvalidError as e:
        instance_error_msgs.append(str(e))
      if not instance_error_msgs:
        parsed_entries.append((parsed_instance_name, parsed_agent_rules))
      error_msgs.extend(instance_error_msgs)
    try:
      self._validate_instances_duplication(
          instance_full_name for instance_full_name, _ in entries)
    except InstanceEntriesDuplicateError as e:
      error_msgs.append(str(e))
    if error_msgs:
      raise EntriesValidationError("\n".join(error_msgs))
    return parsed_entries

  def _display_progress_bar(self,
                            iteration: int,
                            total: int,
                            prefix: str = "",
                            suffix: str = "",
                            decimals: int = 1,
                            length: int = 100) -> None:
    """Displays progress bar."""
    percent_format = f"{{0:.{decimals}%}}"
    # Handle zero total to avoid ZeroDivisionError
    if not total:
      percent = percent_format.format(0)
      filled_length = 0
    else:
      percent = percent_format.format(iteration / total)
      filled_length = int(length * iteration / total)
    bar = "=" * filled_length + "-" * (length - filled_length)
    con = f"\r{_Bold(f'{prefix} |{bar}| {percent} {suffix}') }"
    # Use a newline when complete, otherwise carriage return to overwrite
    end = "\r" if iteration != total else "\n"
    print(con, end=end)

  def _with_rate(self, numerator: int, denominator: int) -> str:
    # denominator could be zero
    if not denominator:
      return f"[{numerator}/0]"
    return f"[{numerator}/{denominator}] ({(numerator/denominator):.1%})"

  def _write_process_output_and_print_status(self,
                                             futures: Iterable[Any]) -> None:
    """Writes instance process output and prints status."""
    print("---------------------Getting output-------------------------")
    success = 0
    failure = 0
    skipped = 0
    total_tasks = len(self.tasks)
    self._display_progress_bar(
        0, total_tasks, prefix="Progress:", suffix="Complete", length=50)

    for i, future in enumerate(concurrent.futures.as_completed(futures)):
      completed = i + 1
      task = future.result()
      if task.status != ProvisioningStatus.SKIPPED:
        task.wait_for_completion()
        self.state[str(task.instance_info)] = {
            "status": task.status.value,
            "last_updated":
                f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%S.%fZ}"
        }
      if task.status == ProvisioningStatus.SUCCESS:
        success += 1
      elif task.status == ProvisioningStatus.FAILURE:
        failure += 1
      elif task.status == ProvisioningStatus.SKIPPED:
        skipped += 1

      self._display_progress_bar(
          completed,
          total_tasks,
          prefix="Progress:",
          suffix=(
              f"{self._with_rate(completed, total_tasks)} completed; "
              f"{self._with_rate(success, completed)} succeeded; "
              f"{self._with_rate(failure, completed)} failed; "
              f"{self._with_rate(skipped, completed)} skipped;"),
          length=50)

    for task in self.tasks:
      if task.status == ProvisioningStatus.SKIPPED:
        print(f"Instance: {task.instance_info} was skipped.")
      else:
        for agent_type, agent_status in task.agents_status.items():
          print(f"Instance: {task.instance_info} {agent_status} {agent_type}. "
                f"See log file in: {task.process_info.log_file}")
    print()
    print(_Bold(f"SUCCEEDED: {self._with_rate(success, total_tasks)}"))
    print(_Bold(f"FAILED: {self._with_rate(failure, total_tasks)}"))
    print(_Bold(f"SKIPPED: {self._with_rate(skipped, total_tasks)}"))
    print(_Bold(f"COMPLETED: {self._with_rate(completed, total_tasks)}"))
    print()

  def run(self):
    """Runs the provisioning tasks."""
    start_time = time.time()
    os.makedirs(self.log_dir, exist_ok=True)
    script_log_file = os.path.join(self.log_dir, "wrapper_script.log")
    fh = logging.FileHandler(script_log_file)
    formatter = logging.Formatter(
        fmt="%(asctime)s.%(msecs)03d %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S")
    formatter.converter = time.gmtime
    fh.setFormatter(formatter)
    _logger.addHandler(fh)
    self._read_state()
    _logger.info("Starting to read entries from file %s.", self.vms_file)
    entries = self._read_entries_from_file()
    _logger.info("Finished reading entried from file %s.", self.vms_file)
    try:
      _logger.info("Starting to parse and validate entries.")
      parsed_entries = self._parse_and_validate_entries(entries)
      _logger.info("Parsed and validated all entries successfully.")
    except EntriesValidationError as e:
      _logger.error("Some entries are invalid or malformed:\n%s", e)
      print(f"ERROR:\n{e}")
      return

    print(f"See log files in folder: {self.log_dir}")
    _logger.info("Starting tasks on instances.")
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=self.max_workers) as executor:
      futures = []
      for parsed_instance_name, agent_rules in parsed_entries:
        instance_full_name = str(parsed_instance_name)
        status = ProvisioningStatus.PENDING
        # Stored states are string values; compare to the enum's value
        if (instance_full_name in self.state and
            self.state[instance_full_name]["status"] ==
            ProvisioningStatus.SUCCESS.value):
          status = ProvisioningStatus.SKIPPED
        task = ProvisioningTask(
          parsed_instance_name,
          agent_rules,
          self.log_dir,
          self.max_retries,
          status=status,
          provider=self.provider_instance)
        self.tasks.append(task)
        futures.append(executor.submit(task.run))
      self._write_process_output_and_print_status(futures)

    self._write_state()
    stop_time = time.time()
    _logger.info("Processed %d VMs in %s seconds.", len(parsed_entries),
                 stop_time - start_time)


def _Bold(content: str) -> str:
  return f"\033[1m{content}\033[0m"


def main():
  _logger.debug("Args passed to the script: %s", sys.argv[1:])
  parser = argparse.ArgumentParser()
  required = parser.add_argument_group("required arguments")
  required.add_argument(
      "--file",
      action="store",
      dest="vms_file",
      required=True,
      help="The path of the input CSV file that contains a list of VMs to "
      "provision the agent on.")
  parser.add_argument(
      "--max-workers",
      action="store",
      dest="max_workers",
      type=int,
      default=10,
      help="The maximum number of concurrent workers.")
  parser.add_argument(
      "--force",
      action="store_true",
      dest="force",
      default=False,
      help="Force re-provisioning of all VMs.")
  parser.add_argument(
      "--max-retries",
      action="store",
      dest="max_retries",
      type=int,
      default=3,
      help="The maximum number of retries for a failed command.")
  parser.add_argument(
      "--provider",
      action="store",
      dest="provider",
      default="local-gcloud",
      help="Execution provider to use. Built-ins: local-gcloud, mock.")
  parser.add_argument(
      "--dry-run",
      action="store_true",
      dest="dry_run",
      default=False,
      help="Perform a dry run using a mock provider (no network calls).")
  parser.add_argument(
      "--ssh-user",
      action="store",
      dest="ssh_user",
      default=None,
      help="SSH username to use with the paramiko provider.")
  parser.add_argument(
      "--ssh-key",
      action="store",
      dest="ssh_key",
      default=None,
      help="Path to private key file to use with the paramiko provider.")
  args = parser.parse_args()

  _logger.setLevel(logging.INFO)
  provisioner = Provisioner(args.vms_file, args.max_workers, args.force,
                            args.max_retries, provider=args.provider,
                            dry_run=args.dry_run, ssh_user=args.ssh_user,
                            ssh_key=args.ssh_key)
  provisioner.run()


if __name__ == "__main__":
  main()
