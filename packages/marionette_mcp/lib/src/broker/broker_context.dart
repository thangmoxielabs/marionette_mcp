import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/broker/broker_server.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Context for routing MCP tool calls through a local broker server
/// to a Flutter app connected via WebSocket.
final class BrokerContext {
  BrokerContext(this.broker) : _logger = logging.Logger('BrokerContext');

  final BrokerServer broker;
  final logging.Logger _logger;

  /// Registers all broker-based tools with the MCP server.
  void registerTools(McpServer server) {
    _registerConnectionTools(server);
    _registerInspectionTools(server);
    _registerGestureTools(server);
    _registerTextTools(server);
    _registerSystemTools(server);
  }

  void _registerConnectionTools(McpServer server) {
    server.registerTool(
      'broker_status',
      description:
          'Checks if a Flutter app is connected to the broker server.',
      annotations: const ToolAnnotations(title: 'Broker Status'),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        if (broker.hasAppConnected) {
          return CallToolResult(
            content: [const TextContent(text: 'App is connected to broker')],
          );
        }
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text: 'No app connected to broker. Launch your Flutter app with marionette enabled.',
            ),
          ],
        );
      },
    );
  }

  void _registerInspectionTools(McpServer server) {
    server.registerTool(
      'get_interactive_elements',
      description:
          'Returns a list of all interactive elements currently visible in the Flutter app UI tree.',
      annotations: const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        _logger.info('Getting interactive elements via broker');
        return runTool(_logger, 'get interactive elements', () async {
          final response = await broker.request('interactiveElements', {});
          final elements = response['elements'] as List<dynamic>;

          final buffer = StringBuffer()
            ..writeln('Found ${elements.length} interactive element(s):\n');

          for (final element in elements) {
            buffer.writeln(formatElement(element as Map<String, dynamic>));
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        });
      },
    );
  }

  void _registerGestureTools(McpServer server) {
    server
      ..registerTool(
        'tap',
        description:
            'Taps on an interactive element in the Flutter app by its ref identifier.',
        annotations: const ToolAnnotations(title: 'Tap'),
        inputSchema: ToolInputSchema(
          properties: {
            'ref': JsonSchema.string(
              description: 'Element ref (e.g., @1) from get_interactive_elements.',
            ),
          },
          required: ['ref'],
        ),
        callback: (args, extra) async {
          final ref = args['ref'] as String;
          _logger.info('Tapping $ref via broker');
          return runTool(_logger, 'tap', () async {
            await broker.request('tap', {'ref': ref});
            return CallToolResult(
              content: [TextContent(text: 'Tapped element $ref')],
            );
          });
        },
      )
      ..registerTool(
        'double_tap',
        description: 'Double-taps on an interactive element.',
        annotations: const ToolAnnotations(title: 'Double Tap'),
        inputSchema: ToolInputSchema(
          properties: {
            'ref': JsonSchema.string(
              description: 'Element ref.',
            ),
          },
          required: ['ref'],
        ),
        callback: (args, extra) async {
          final ref = args['ref'] as String;
          _logger.info('Double-tapping $ref via broker');
          return runTool(_logger, 'double tap', () async {
            await broker.request('doubleTap', {'ref': ref});
            return CallToolResult(
              content: [TextContent(text: 'Double-tapped element $ref')],
            );
          });
        },
      )
      ..registerTool(
        'long_press',
        description: 'Long-presses on an interactive element.',
        annotations: const ToolAnnotations(title: 'Long Press'),
        inputSchema: ToolInputSchema(
          properties: {
            'ref': JsonSchema.string(description: 'Element ref.'),
            'duration': JsonSchema.string(
              description: 'Duration in ms (default: 500).',
            ),
          },
          required: ['ref'],
        ),
        callback: (args, extra) async {
          final ref = args['ref'] as String;
          final duration = args['duration'] as String?;
          _logger.info('Long-pressing $ref via broker');
          return runTool(_logger, 'long press', () async {
            await broker.request('longPress', {
              'ref': ref,
              if (duration != null) 'duration': duration,
            });
            return CallToolResult(
              content: [TextContent(text: 'Long-pressed element $ref')],
            );
          });
        },
      )
      ..registerTool(
        'scroll_to',
        description: 'Scrolls to an interactive element.',
        annotations: const ToolAnnotations(title: 'Scroll To'),
        inputSchema: ToolInputSchema(
          properties: {
            'ref': JsonSchema.string(description: 'Element ref.'),
          },
          required: ['ref'],
        ),
        callback: (args, extra) async {
          final ref = args['ref'] as String;
          _logger.info('Scrolling to $ref via broker');
          return runTool(_logger, 'scroll to', () async {
            await broker.request('scrollTo', {'ref': ref});
            return CallToolResult(
              content: [TextContent(text: 'Scrolled to element $ref')],
            );
          });
        },
      );
  }

  void _registerTextTools(McpServer server) {
    server.registerTool(
      'enter_text',
      description: 'Enters text into a text input element.',
      annotations: const ToolAnnotations(title: 'Enter Text'),
      inputSchema: ToolInputSchema(
        properties: {
          'ref': JsonSchema.string(description: 'Element ref.'),
          'text': JsonSchema.string(description: 'Text to enter.'),
        },
        required: ['ref', 'text'],
      ),
      callback: (args, extra) async {
        final ref = args['ref'] as String;
        final text = args['text'] as String;
        _logger.info('Entering text into $ref via broker');
        return runTool(_logger, 'enter text', () async {
          await broker.request('enterText', {'ref': ref, 'text': text});
          return CallToolResult(
            content: [TextContent(text: 'Entered text into element $ref')],
          );
        });
      },
    );
  }

  void _registerSystemTools(McpServer server) {
    server
      ..registerTool(
        'hot_reload',
        description: 'Performs a hot reload of the Flutter app.',
        annotations: const ToolAnnotations(title: 'Hot Reload'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Hot reload via broker');
          return runTool(_logger, 'hot reload', () async {
            await broker.request('hotReload', {});
            return CallToolResult(
              content: [const TextContent(text: 'Hot reload triggered')],
            );
          });
        },
      )
      ..registerTool(
        'press_back_button',
        description: 'Presses the back button.',
        annotations: const ToolAnnotations(title: 'Press Back Button'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Press back button via broker');
          return runTool(_logger, 'press back button', () async {
            final result = await broker.request('pressBackButton', {});
            return CallToolResult(
              content: [TextContent(text: result['message'] as String)],
            );
          });
        },
      );
  }
}
