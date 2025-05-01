import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('利用規約'),
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 53, 152, 71),
                Color.fromARGB(255, 40, 130, 60),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '利用規約',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '本利用規約（以下「本規約」）は、本アプリ「暗記Pai」（以下「本アプリ」）の利用条件を定めるものです。ユーザーの皆様には、本規約に従って本アプリをご利用いただきます。',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '第1条（適用）',
              '1. 本規約は、ユーザーと本アプリの利用に関わる一切の関係に適用されるものとします。\n'
                  '2. 本アプリは本規約のほか、ご利用に関するルールを定めることがあります。これらのルールは本規約の一部を構成するものとします。',
            ),
            _buildSection(
              '第2条（利用登録）',
              '1. 本アプリの利用を希望する者は、本アプリの定める方法によって利用登録を申請し、本アプリがこれを承認することによって、利用登録が完了するものとします。\n'
                  '2. 本アプリは、利用登録の申請者に以下の事由があると判断した場合、利用登録の申請を承認しないことがあります。\n'
                  '・申請に際して虚偽の事項を届け出た場合\n'
                  '・本規約に違反したことがある者からの申請である場合\n'
                  '・その他、本アプリが利用登録を相当でないと判断した場合',
            ),
            _buildSection(
              '第3条（ユーザーIDおよびパスワードの管理）',
              '1. ユーザーは、自己の責任において、本アプリのユーザーIDおよびパスワードを適切に管理するものとします。\n'
                  '2. ユーザーID及びパスワードが第三者によって使用されたことによって生じた損害は、本アプリに故意又は重大な過失がある場合を除き、本アプリは一切の責任を負わないものとします。',
            ),
            _buildSection(
              '第4条（禁止事項）',
              '本アプリの利用にあたり、以下の行為を禁止します。\n'
                  '・法令または公序良俗に違反する行為\n'
                  '・犯罪行為に関連する行為\n'
                  '・本アプリの他のユーザー、または第三者のサーバーまたはネットワークの機能を破壊したり、妨害したりする行為\n'
                  '・本アプリのサービスの運営を妨害するおそれのある行為\n'
                  '・不正アクセスをし、またはこれを試みる行為\n'
                  '・他のユーザーに関する個人情報等を収集または蓄積する行為\n'
                  '・不正な目的を持って本アプリを利用する行為\n'
                  '・本アプリの他のユーザーまたはその他の第三者に不利益、損害、不快感を与える行為\n'
                  '・他のユーザーに成りすます行為\n'
                  '・本アプリが許諾しない本アプリ上での宣伝、広告、勧誘、または営業行為\n'
                  '・面識のない異性との出会いを目的とした行為\n'
                  '・本アプリに関連して、反社会的勢力に対して直接または間接に利益を供与する行為\n'
                  '・その他、本アプリが不適切と判断する行為',
            ),
            _buildSection(
              '第5条（本アプリの提供の停止等）',
              '1. 本アプリは、以下のいずれかの事由があると判断した場合、ユーザーに事前に通知することなく本アプリの全部または一部の提供を停止または中断することができるものとします。\n'
                  '・本アプリにかかるコンピュータシステムの保守点検または更新を行う場合\n'
                  '・地震、落雷、火災、停電または天災などの不可抗力により、本アプリの提供が困難となった場合\n'
                  '・コンピュータまたは通信回線等が事故により停止した場合\n'
                  '・その他、本アプリが本アプリの提供が困難と判断した場合\n'
                  '2. 本アプリは、本アプリの提供の停止または中断により、ユーザーまたは第三者が被ったいかなる不利益または損害についても、一切の責任を負わないものとします。',
            ),
            _buildSection(
              '第6条（利用制限および登録抹消）',
              '本アプリは、ユーザーが以下のいずれかに該当する場合には、事前の通知なく、ユーザーに対して、本アプリの全部もしくは一部の利用を制限し、またはユーザーとしての登録を抹消することができるものとします。\n'
                  '・本規約のいずれかの条項に違反した場合\n'
                  '・登録事項に虚偽の事実があることが判明した場合\n'
                  '・その他、本アプリが本アプリの利用を適当でないと判断した場合',
            ),
            _buildSection(
              '第7条（退会）',
              'ユーザーは、本アプリの定める退会手続により、本アプリから退会できるものとします。',
            ),
            _buildSection(
              '第8条（保証の否認および免責事項）',
              '1. 本アプリは、本アプリに事実上または法律上の瑕疵（安全性、信頼性、正確性、完全性、有効性、特定の目的への適合性、セキュリティなどに関する欠陥、エラーやバグ、権利侵害などを含みます。）がないことを明示的にも黙示的にも保証しておりません。\n'
                  '2. 本アプリは、本アプリに起因してユーザーに生じたあらゆる損害について一切の責任を負いません。',
            ),
            _buildSection(
              '第9条（サービス内容の変更等）',
              '本アプリは、ユーザーに通知することなく、本アプリの内容を変更しまたは本アプリの提供を中止することができるものとし、これによってユーザーに生じた損害について一切の責任を負いません。',
            ),
            _buildSection(
              '第10条（利用規約の変更）',
              '本アプリは、必要と判断した場合には、ユーザーに通知することなくいつでも本規約を変更することができるものとします。なお、本規約の変更後、本アプリの利用を開始した場合には、当該ユーザーは変更後の規約に同意したものとみなします。',
            ),
            _buildSection(
              '第11条（個人情報の取扱い）',
              '本アプリの利用によって取得する個人情報については、本アプリの「プライバシーポリシー」に従い適切に取り扱うものとします。',
            ),
            _buildSection(
              '第12条（通知または連絡）',
              '1. ユーザーと本アプリとの間の通知または連絡は、本アプリの定める方法によって行うものとします。\n'
                  '2. 本アプリは、ユーザーから、本アプリが別途定める方式に従った変更届け出がない限り、現在登録されている連絡先が有効なものとみなして当該連絡先へ通知または連絡を行い、これらは、発信時にユーザーへ到達したものとみなします。',
            ),
            _buildSection(
              '第13条（権利義務の譲渡の禁止）',
              'ユーザーは、本アプリの書面による事前の承諾なく、利用契約上の地位または本規約に基づく権利もしくは義務を第三者に譲渡し、または担保に供することはできません。',
            ),
            _buildSection(
              '第14条（準拠法・裁判管轄）',
              '1. 本規約の解釈にあたっては、日本法を準拠法とします。\n'
                  '2. 本アプリに関して紛争が生じた場合には、本アプリの運営者の所在地を管轄する裁判所を専属的合意管轄とします。',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '2025年4月15日改訂',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
