import 'package:dowel/dowel.dart';

import 'commands/doctor_command.dart' as deeplink_doctor;
import 'commands/generate_command.dart';
import 'commands/install_command.dart';

/// Dowel provider that registers all magic_deeplink CLI commands.
class MagicDeeplinkDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'magic_deeplink';

  @override
  List<DowelCommand> commands() => <DowelCommand>[
    InstallCommand(),
    GenerateCommand(),
    deeplink_doctor.DoctorCommand(),
  ];
}
