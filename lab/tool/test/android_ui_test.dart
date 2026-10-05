import 'package:test/test.dart';
import 'package:tremulator_lab/android_ui.dart';

const xml = '''
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">
<node index="0" text="" resource-id="com.whatsapp:id/conversation_contact_name" class="android.widget.TextView" content-desc="" bounds="[200,180][700,260]" />
<node index="1" text="Dr Example" resource-id="com.whatsapp:id/conversation_contact_name" class="android.widget.TextView" content-desc="" bounds="[200,180][700,260]" />
<node index="2" text="" resource-id="" class="android.widget.ImageButton" content-desc="Voice call" bounds="[964,155][1132,323]" />
<node index="3" text="first &amp; older" resource-id="com.whatsapp:id/message_text" class="android.widget.TextView" content-desc="" bounds="[100,400][900,460]" />
<node index="4" text="" resource-id="com.whatsapp:id/status" class="android.widget.ImageView" content-desc="Read" bounds="[1110,390][1180,432]" />
<node index="5" text="newest outgoing" resource-id="com.whatsapp:id/message_text" class="android.widget.TextView" content-desc="" bounds="[100,800][900,860]" />
<node index="6" text="" resource-id="com.whatsapp:id/status" class="android.widget.ImageView" content-desc="Delivered" bounds="[1110,881][1180,923]" />
<node index="7" text="" resource-id="com.whatsapp:id/entry" class="android.widget.EditText" content-desc="" bounds="[196,2560][708,2673]" />
</hierarchy>
''';

void main() {
  final nodes = parseNodes(xml);
  test('parses every node with bounds and unescapes text', () {
    expect(nodes.length, 8);
    expect(nodes[3].text, 'first & older');
    expect(nodes[2].center, (1048, 239));
  });
  test('byId and byDesc', () {
    expect(byId(nodes, 'entry')!.bounds, (196, 2560, 708, 2673));
    expect(byId(nodes, 'nope'), isNull);
    expect(byDesc(nodes, 'Voice call')!.center.$1, 1048);
  });
  test('lastStatus is the lowest tick, lastMessageText the lowest bubble', () {
    expect(lastStatus(nodes)!.desc, 'Delivered');
    expect(lastMessageText(nodes)!.text, 'newest outgoing');
    expect(newestIsIncoming(nodes), isFalse);
  });
  test('an incoming bubble below every tick is incoming', () {
    const incoming =
        '<node index="9" text="reply from iPhone" '
        'resource-id="com.whatsapp:id/message_text" class="x" '
        'content-desc="" bounds="[100,1200][900,1260]" />';
    final ns = parseNodes(
      xml.replaceFirst('</hierarchy>', '$incoming</hierarchy>'),
    );
    expect(newestIsIncoming(ns), isTrue);
    expect(lastMessageText(ns)!.text, 'reply from iPhone');
  });
}
