const FORM_CONFIG = Object.freeze({
  FORM_ID: '',
  FORM_TITLE: 'KomuraSoft 開発依頼・技術相談フォーム',
  FORM_DESCRIPTION:
    '開発依頼だけでなく、技術相談・設計レビュー・不具合調査のご相談も受け付けています。内容確認後、対応可否と進め方をご案内します。具体的な調査・レビュー・原因分析が必要な場合は、有償対応としてご案内します。',
  CONFIRMATION_MESSAGE:
    'お問い合わせありがとうございます。内容を確認し、通常2〜3営業日以内にご返信します。技術相談の場合は、必要に応じて進め方や有償対応の有無をご案内します。',
  CLEAR_EXISTING_ITEMS: false,
  ALLOW_CLEAR_WITH_RESPONSES: false
});

const SECTION_TITLES = Object.freeze({
  technical: '技術相談',
  development: '開発依頼',
  maintenance: '既存システムの改修・保守',
  other: 'その他'
});

function buildKomuraSoftInquiryForm() {
  const form = getOrCreateForm_();
  prepareForm_(form);

  const common = createCommonSection_(form);
  const sections = {
    technical: createTechnicalConsultingSection_(form),
    development: createDevelopmentSection_(form),
    maintenance: createMaintenanceSection_(form),
    other: createOtherSection_(form)
  };
  setInquiryTypeChoices_(common.inquiryType, sections);

  Logger.log('Form edit URL: ' + form.getEditUrl());
  Logger.log('Form published URL: ' + form.getPublishedUrl());

  const links = createDefaultPrefilledUrls_(form);
  Logger.log('Generic URL: ' + links.generic);
  Logger.log('Technical consultation URL: ' + links.technicalConsultation);
  Logger.log('Article template URL: ' + links.articleTemplate);
}

function logArticlePrefilledUrl() {
  const form = openConfiguredForm_();
  const articleReference = 'REPLACE_WITH_ARTICLE_TITLE_OR_URL';
  const url = createPrefilledUrl_(form, {
    'お問い合わせ種別': '技術相談',
    '参考にした記事 / ページ': articleReference
  });

  Logger.log(url);
}

function getOrCreateForm_() {
  if (!FORM_CONFIG.FORM_ID) {
    return FormApp.create(FORM_CONFIG.FORM_TITLE);
  }

  return openConfiguredForm_();
}

function openConfiguredForm_() {
  if (!FORM_CONFIG.FORM_ID) {
    throw new Error('FORM_CONFIG.FORM_ID が空です。既存フォームを開く場合は ID を設定してください。');
  }

  return FormApp.openById(FORM_CONFIG.FORM_ID);
}

function prepareForm_(form) {
  form.setTitle(FORM_CONFIG.FORM_TITLE);
  form.setDescription(FORM_CONFIG.FORM_DESCRIPTION);
  form.setConfirmationMessage(FORM_CONFIG.CONFIRMATION_MESSAGE);

  const items = form.getItems();
  if (items.length === 0) {
    return;
  }

  if (!FORM_CONFIG.CLEAR_EXISTING_ITEMS) {
    throw new Error(
      '既存フォームに項目があります。重複作成を避けるため停止しました。新規フォームを作るか、CLEAR_EXISTING_ITEMS を true にしてください。'
    );
  }

  const responseCount = form.getResponses().length;
  if (responseCount > 0 && !FORM_CONFIG.ALLOW_CLEAR_WITH_RESPONSES) {
    throw new Error(
      '既存フォームに回答が ' + responseCount + ' 件あります。既存回答があるフォームを消して再構成する前に、フォームを複製するか、ALLOW_CLEAR_WITH_RESPONSES を確認してください。'
    );
  }

  clearFormItems_(form);
}

function clearFormItems_(form) {
  const items = form.getItems();
  for (let index = items.length - 1; index >= 0; index -= 1) {
    form.deleteItem(items[index]);
  }
}

function createCommonSection_(form) {
  form.addTextItem()
    .setTitle('メールアドレス')
    .setRequired(true);

  form.addTextItem()
    .setTitle('お名前')
    .setRequired(true);

  form.addTextItem()
    .setTitle('会社名 / 組織名')
    .setRequired(false);

  const inquiryType = form.addMultipleChoiceItem();
  inquiryType.setTitle('お問い合わせ種別');
  inquiryType.setRequired(true);

  form.addTextItem()
    .setTitle('参考にした記事 / ページ')
    .setRequired(false)
    .setHelpText('ブログ記事や案内ページを見てお問い合わせいただいた場合は、その記事タイトルや URL を入れてください。');

  return { inquiryType: inquiryType };
}

function setInquiryTypeChoices_(inquiryType, sections) {
  inquiryType.setChoices([
    inquiryType.createChoice('開発依頼', sections.development),
    inquiryType.createChoice('技術相談', sections.technical),
    inquiryType.createChoice('既存システムの改修・保守', sections.maintenance),
    inquiryType.createChoice('その他', sections.other)
  ]);
}

function createTechnicalConsultingSection_(form) {
  const section = form.addPageBreakItem().setTitle(SECTION_TITLES.technical);

  form.addTextItem()
    .setTitle('ご相談テーマ')
    .setRequired(true)
    .setHelpText('例: WPFアプリのフリーズ原因を切り分けたい / COMの移行方針を相談したい');

  form.addParagraphTextItem()
    .setTitle('現在の状況')
    .setRequired(true)
    .setHelpText('何が起きているか、どこで詰まっているか、今わかっている範囲で書いてください。');

  const technology = form.addCheckboxItem();
  technology.setTitle('対象技術');
  technology.setRequired(false);
  technology.setChoices([
    technology.createChoice('C#'),
    technology.createChoice('.NET'),
    technology.createChoice('WPF'),
    technology.createChoice('WinForms'),
    technology.createChoice('C++'),
    technology.createChoice('C++/CLI'),
    technology.createChoice('COM'),
    technology.createChoice('ActiveX'),
    technology.createChoice('Windows API'),
    technology.createChoice('その他')
  ]);

  const goal = form.addMultipleChoiceItem();
  goal.setTitle('期待するゴール');
  goal.setRequired(true);
  goal.setChoices([
    goal.createChoice('方針整理'),
    goal.createChoice('設計レビュー'),
    goal.createChoice('原因切り分け'),
    goal.createChoice('改修相談'),
    goal.createChoice('セカンドオピニオン'),
    goal.createChoice('その他')
  ]);

  const communication = form.addMultipleChoiceItem();
  communication.setTitle('希望する進め方');
  communication.setRequired(false);
  communication.setChoices([
    communication.createChoice('メールでのやり取り'),
    communication.createChoice('オンライン打ち合わせ'),
    communication.createChoice('どちらでもよい')
  ]);

  const materials = form.addMultipleChoiceItem();
  materials.setTitle('関連資料の有無');
  materials.setRequired(false);
  materials.setChoices([
    materials.createChoice('あり'),
    materials.createChoice('なし')
  ]);

  form.addParagraphTextItem()
    .setTitle('備考')
    .setRequired(false);

  return section;
}

function createDevelopmentSection_(form) {
  const section = form.addPageBreakItem().setTitle(SECTION_TITLES.development);

  form.addParagraphTextItem()
    .setTitle('依頼したい内容')
    .setRequired(true);

  form.addParagraphTextItem()
    .setTitle('対象システム / 対象環境')
    .setRequired(false);

  form.addTextItem()
    .setTitle('希望時期')
    .setRequired(false);

  form.addParagraphTextItem()
    .setTitle('備考')
    .setRequired(false);

  return section;
}

function createMaintenanceSection_(form) {
  const section = form.addPageBreakItem().setTitle(SECTION_TITLES.maintenance);

  form.addParagraphTextItem()
    .setTitle('対象システムの概要')
    .setRequired(true);

  form.addParagraphTextItem()
    .setTitle('困っていること')
    .setRequired(true);

  const technology = form.addCheckboxItem();
  technology.setTitle('対象技術');
  technology.setRequired(false);
  technology.setChoices([
    technology.createChoice('C#'),
    technology.createChoice('.NET'),
    technology.createChoice('WPF'),
    technology.createChoice('WinForms'),
    technology.createChoice('C++'),
    technology.createChoice('C++/CLI'),
    technology.createChoice('COM'),
    technology.createChoice('ActiveX'),
    technology.createChoice('Windows API'),
    technology.createChoice('その他')
  ]);

  const support = form.addMultipleChoiceItem();
  support.setTitle('希望する支援');
  support.setRequired(true);
  support.setChoices([
    support.createChoice('仕様把握'),
    support.createChoice('不具合修正'),
    support.createChoice('性能改善'),
    support.createChoice('リファクタリング'),
    support.createChoice('移行相談'),
    support.createChoice('その他')
  ]);

  form.addParagraphTextItem()
    .setTitle('備考')
    .setRequired(false);

  return section;
}

function createOtherSection_(form) {
  const section = form.addPageBreakItem().setTitle(SECTION_TITLES.other);

  form.addParagraphTextItem()
    .setTitle('お問い合わせ内容')
    .setRequired(true);

  return section;
}

function createDefaultPrefilledUrls_(form) {
  return {
    generic: createPrefilledUrl_(form, {}),
    technicalConsultation: createPrefilledUrl_(form, {
      'お問い合わせ種別': '技術相談'
    }),
    articleTemplate: createPrefilledUrl_(form, {
      'お問い合わせ種別': '技術相談',
      '参考にした記事 / ページ': 'REPLACE_WITH_ARTICLE_TITLE_OR_URL'
    })
  };
}

function createPrefilledUrl_(form, valuesByTitle) {
  const items = form.getItems();
  const params = ['usp=pp_url'];

  Object.keys(valuesByTitle).forEach(function (title) {
    const item = items.find(function (candidate) {
      return candidate.getTitle() === title;
    });

    if (!item) {
      throw new Error('指定したタイトルの質問が見つかりません: ' + title);
    }

    const entryName = 'entry.' + item.getId();
    const value = valuesByTitle[title];

    if (Array.isArray(value)) {
      value.forEach(function (singleValue) {
        params.push(entryName + '=' + encodeURIComponent(String(singleValue)));
      });
      return;
    }

    params.push(entryName + '=' + encodeURIComponent(String(value)));
  });

  return form.getPublishedUrl().split('?')[0] + '?' + params.join('&');
}
