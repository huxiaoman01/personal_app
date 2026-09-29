import 'package:flutter/material.dart';

import '../../models/study_card.dart';

/// 一个「卡片库 + 复习」功能的配置：类型 + 几处文案。
///
/// 记忆卡和错题本是同一套页面（同样的筛选条、复习条、翻卡、记得/忘了），
/// 只有字不一样。把这些字集中到这里，改文案不用翻页面代码；以后「问题
/// 收集箱」要是也走这套页面，再加一个 const 实例就行。
///
/// 写法照首页的 `HubEntry`：一个 const 类 + 几个 const 实例。
class CardFeature {
  const CardFeature({
    required this.type,
    required this.title,
    required this.editVerb,
    required this.icon,
    required this.emptyText,
    required this.emptyFilteredText,
    required this.reviewedWord,
    required this.revealHint,
    required this.emptyFlipText,
    required this.forgotLabel,
    required this.rememberedLabel,
  });

  /// 卡片类型，存库时用的那个字符串。
  final String type;

  /// 列表页标题：「记忆卡片」/「错题本」。
  final String title;

  /// 编辑页标题里的动作对象：「新增记忆卡」/「编辑错题」。
  final String editVerb;

  /// 空态的图标。
  final IconData icon;

  /// 一张卡都没有时的提示。
  final String emptyText;

  /// 筛选之后一张都没有时的提示。
  final String emptyFilteredText;

  /// 复习次数的说法：「忘了 N 次」/「错了 N 次」。
  final String reviewedWord;

  /// 卡片还没翻开时的提示。
  final String revealHint;

  /// 翻开了但正文是空的。
  final String emptyFlipText;

  /// 底部左边那个按钮（没答上来）。
  final String forgotLabel;

  /// 底部右边那个按钮（答上来了）。
  final String rememberedLabel;
}

const CardFeature memoryFeature = CardFeature(
  type: CardType.memory,
  title: '记忆卡片',
  editVerb: '记忆卡',
  icon: Icons.style_outlined,
  emptyText: '还没有记忆卡\n点右下角 + 写第一条',
  emptyFilteredText: '这个筛选下还没有记忆卡',
  reviewedWord: '忘了',
  revealHint: '点一下看答案',
  emptyFlipText: '（这条没有写答案）',
  forgotLabel: '忘了',
  rememberedLabel: '记得',
);

const CardFeature mistakeFeature = CardFeature(
  type: CardType.mistake,
  title: '错题本',
  editVerb: '错题',
  icon: Icons.error_outline,
  emptyText: '还没有错题\n点右下角 + 拍下第一道',
  emptyFilteredText: '这个筛选下还没有错题',
  reviewedWord: '错了',
  revealHint: '点一下看错在哪',
  emptyFlipText: '（这条没写错在哪）',
  forgotLabel: '又错了',
  rememberedLabel: '做对了',
);

/// 已经接入「卡片库 + 复习」这套页面的功能。
const List<CardFeature> kCardFeatures = <CardFeature>[
  memoryFeature,
  mistakeFeature,
];

/// 按类型查配置；还没接入的类型（公式、灵感、问题）返回 null。
CardFeature? cardFeatureOf(String? type) {
  for (final CardFeature feature in kCardFeatures) {
    if (feature.type == type) return feature;
  }
  return null;
}
