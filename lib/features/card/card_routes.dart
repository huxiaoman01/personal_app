import 'package:flutter/material.dart';

import '../../models/study_card.dart';
import '../formula/card_detail_screen.dart';
import '../question/question_detail_screen.dart';
import 'card_edit_screen.dart';

/// 按卡片类型决定「点开这条卡片」跳哪个页面。
///
/// 公式卡要先看大图和科目，所以进详情页；灵感是纯文字、以随时补两笔为主，
/// 点开直接进编辑页，省一层跳转；问题要的就是当场回填答案，所以有自己
/// 的详情页。以后加别的功能，在这里补一条分支就行。
Route<void> routeForCard(StudyCard card) {
  if (card.type == CardType.idea) {
    return MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          CardEditScreen(type: CardType.idea, card: card),
    );
  }
  if (card.type == CardType.question) {
    return MaterialPageRoute<void>(
      builder: (BuildContext _) => QuestionDetailScreen(cardId: card.id!),
    );
  }
  return MaterialPageRoute<void>(
    builder: (BuildContext _) => CardDetailScreen(cardId: card.id!),
  );
}
