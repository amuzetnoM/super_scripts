#!/usr/bin/env python3
import unittest
from unittest import mock

from mass_provision_google_cloud_ops_agents import AgentRuleInvalidError
from mass_provision_google_cloud_ops_agents import AgentRuleParseError
from mass_provision_google_cloud_ops_agents import EntriesValidationError
from mass_provision_google_cloud_ops_agents import InstanceFullNameInvalidError
from mass_provision_google_cloud_ops_agents import InstanceInfo
from mass_provision_google_cloud_ops_agents import Provisioner
from mass_provision_google_cloud_ops_agents import ProvisioningTask


class MassProvisionTest(unittest.TestCase):

  def setUp(self):
    self.provisioner = Provisioner("fake_vms_file", max_retries=1)

  def test_ParseAndValidateInstanceFullName_success(self):
    instance_full_name = "projects/my-project/zones/us-central1-a/instances/my-instance"
    expected = InstanceInfo("my-project", "us-central1-a", "my-instance")
    self.assertEqual(
        self.provisioner._parse_and_validate_instance_full_name(
            instance_full_name), expected)

  def test_ParseAndValidateInstanceFullName_failure(self):
    with self.assertRaises(InstanceFullNameInvalidError):
      self.provisioner._parse_and_validate_instance_full_name("invalid-name")

  def test_ExtractAgentRules_success(self):
    agent_rules_str = '[{"type": "logging", "version": "1.2.3"}]'
    expected = [{"type": "logging", "version": "1.2.3"}]
    self.assertEqual(
        self.provisioner._extract_agent_rules("instance-name", agent_rules_str),
        expected)

  def test_ExtractAgentRules_invalidJson(self):
    with self.assertRaises(AgentRuleParseError):
      self.provisioner._extract_agent_rules("instance-name", "invalid-json")

  def test_ExtractAgentRules_missingType(self):
    with self.assertRaises(AgentRuleParseError):
      self.provisioner._extract_agent_rules("instance-name",
                                            '[{"version": "1.2.3"}]')

  def test_ValidateAgentTypes_success(self):
    agent_rules = [{"type": "logging"}, {"type": "metrics"}]
    self.assertEqual(self.provisioner._validate_agent_types(agent_rules), [])

  def test_ValidateAgentTypes_opsAgentWithOther(self):
    agent_rules = [{"type": "ops-agent"}, {"type": "logging"}]
    self.assertTrue(self.provisioner._validate_agent_types(agent_rules))

  def test_ValidateAgentTypes_duplicate(self):
    agent_rules = [{"type": "logging"}, {"type": "logging"}]
    self.assertTrue(self.provisioner._validate_agent_types(agent_rules))

  def test_ValidateAgentTypes_invalid(self):
    agent_rules = [{"type": "invalid-type"}]
    errors = self.provisioner._validate_agent_types(agent_rules)
    self.assertTrue(errors)
    self.assertIn("Invalid agent type: invalid-type", errors[0])

  def test_ValidateAgentVersion_latest(self):
    self.assertEqual(self.provisioner._validate_agent_version("latest"), [])

  def test_ValidateAgentVersion_pinned(self):
    self.assertEqual(self.provisioner._validate_agent_version("1.2.3"), [])

  def test_ValidateAgentVersion_major(self):
    self.assertEqual(self.provisioner._validate_agent_version("1.*.*"), [])

  def test_ValidateAgentVersion_invalid(self):
    self.assertTrue(self.provisioner._validate_agent_version("invalid"))

  def test_ParseAndValidateAgentRules_success(self):
    agent_rules_str = '[{"type": "logging", "version": "1.*.*"}]'
    expected = [{"type": "logging", "version": "1.*.*"}]
    self.assertEqual(
        self.provisioner._parse_and_validate_agent_rules(
            "instance-name", agent_rules_str), expected)

  def test_ParseAndValidateAgentRules_failure(self):
    with self.assertRaises(AgentRuleInvalidError):
      self.provisioner._parse_and_validate_agent_rules(
          "instance-name", '[{"type": "invalid"}]')

  def test_ParseAndValidateEntries_success(self):
    entries = [("projects/p/zones/z/instances/i", '[{"type": "logging"}]')]
    parsed_entries = self.provisioner._parse_and_validate_entries(entries)
    self.assertEqual(len(parsed_entries), 1)

  def test_ParseAndValidateEntries_duplicateInstances(self):
    entries = [
        ("projects/p/zones/z/instances/i", '[{"type": "logging"}]'),
        ("projects/p/zones/z/instances/i", '[{"type": "metrics"}]')
    ]
    with self.assertRaises(EntriesValidationError):
      self.provisioner._parse_and_validate_entries(entries)

  def test_ReadEntriesFromFile_success(self):
    mock_file_content = '"projects/p/zones/z/instances/i","[{\\"type\\": \\\"logging\\"}]"'
    with mock.patch("builtins.open",
                    mock.mock_open(read_data=mock_file_content)):
      entries = self.provisioner._read_entries_from_file()
      self.assertEqual(len(entries), 1)
      self.assertEqual(entries[0][0], "projects/p/zones/z/instances/i")

  def test_ReadEntriesFromFile_malformed(self):
    mock_file_content = '"just_one_field"'
    with mock.patch("builtins.open",
                    mock.mock_open(read_data=mock_file_content)):
      with self.assertRaises(Exception):
        self.provisioner._read_entries_from_file()

  @mock.patch("cloud_ops_provisioning._popen")
  def test_StartProcess_retry(self, mock_popen):
    mock_process = mock.Mock()
    mock_process.wait.return_value = 1
    mock_popen.return_value = mock_process

    instance_info = InstanceInfo("p", "z", "i")
    agent_rules = [{"type": "logging"}]
    task = ProvisioningTask(
        instance_info, agent_rules, "/tmp", max_retries=3)
    with self.assertRaises(Exception):
      task._start_process()
    self.assertEqual(mock_popen.call_count, 3)


if __name__ == '__main__':
  unittest.main()
