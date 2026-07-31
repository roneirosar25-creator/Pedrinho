//+——————————————————————————————————————————————————————————————————+
//|                                                   C_AO_DOA_dream |
//|                                  Copyright 2007-2025, Andrey Dik |
//|                                https://www.mql5.com/ru/users/joo |
//+——————————————————————————————————————————————————————————————————+

#include "#C_AO.mqh"

//————————————————————————————————————————————————————————————————————
class C_AO_DOA_dream : public C_AO
{
  public: //----------------------------------------------------------
  ~C_AO_DOA_dream () { }
  C_AO_DOA_dream ()
  {
    ao_name = "DOA";
    ao_desc = "Dream Optimization Algorithm";
    ao_link = "https://www.mql5.com/ru/articles/19177";

    popSize              = 60;    // размер популяции
    numGroups            = 6;     // количество групп (фиксировано в оригинале)
    explorationRate      = 0.99;  // доля итераций для фазы исследования (9/10 в оригинале)
    forgettingProb       = 0.3;   // вероятность применения основной стратегии забывания

    ArrayResize (params, 4);

    params [0].name = "popSize";           params [0].val = popSize;
    params [1].name = "numGroups";         params [1].val = numGroups;
    params [2].name = "explorationRate";   params [2].val = explorationRate;
    params [3].name = "forgettingProb";    params [3].val = forgettingProb;
  }

  void SetParams ()
  {
    popSize          = (int)params [0].val;
    numGroups        = (int)params [1].val;
    explorationRate  = params      [2].val;
    forgettingProb   = params      [3].val;
  }

  bool Init (const double &rangeMinP  [],
             const double &rangeMaxP  [],
             const double &rangeStepP [],
             const int     epochsP = 0);

  void Moving   ();
  void Revision ();

  //------------------------------------------------------------------
  int    numGroups;         // количество групп
  double explorationRate;   // доля итераций для фазы исследования
  double forgettingProb;    // вероятность применения основной стратегии

  private: //---------------------------------------------------------
  int    currentIteration;  // текущая итерация
  int    totalIterations;   // общее количество итераций
  int    explorationIters;  // количество итераций исследования

  S_AO_Agent groupBest [];  // лучшие решения в каждой группе

  void   ExplorationPhase      ();
  void   ExploitationPhase     ();
  void   UpdateGroupBest       (int groupNum);
  int    GetGroupStartIndex    (int groupNum);
  int    GetGroupEndIndex      (int groupNum);
};
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Инициализация
bool C_AO_DOA_dream::Init (const double &rangeMinP  [],
                           const double &rangeMaxP  [],
                           const double &rangeStepP [],
                           const int     epochsP = 0)
{
  if (!StandardInit (rangeMinP, rangeMaxP, rangeStepP)) return false;

  //------------------------------------------------------------------
  currentIteration = 0;
  totalIterations  = epochsP;
  explorationIters = (int)(totalIterations * explorationRate);

  ArrayResize (groupBest, numGroups);
  for (int i = 0; i < numGroups; i++)
  {
    groupBest [i].Init (coords);
    groupBest [i].f = -DBL_MAX; // Инициализация худшим значением
  }

  return true;
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Основной шаг алгоритма
void C_AO_DOA_dream::Moving ()
{
  currentIteration++;

  // Начальная инициализация популяции
  if (!revision)
  {
    for (int i = 0; i < popSize; i++)
    {
      for (int j = 0; j < coords; j++)
      {
        a [i].c [j] = u.RNDfromCI (rangeMin [j], rangeMax [j]);
        a [i].c [j] = u.SeInDiSp (a [i].c [j], rangeMin [j], rangeMax [j], rangeStep [j]);
      }
    }

    revision = true;
    return;
  }

  //------------------------------------------------------------------
  // Определяем фазу алгоритма
  if (currentIteration <= explorationIters)
  {
    ExplorationPhase ();
  }
  else
  {
    ExploitationPhase ();
  }
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Фаза исследования (Exploration phase)
void C_AO_DOA_dream::ExplorationPhase ()
{
  // Обрабатываем каждую группу
  for (int m = 0; m < numGroups; m++)
  {
    // Обновляем лучшее решение в группе
    UpdateGroupBest (m);

    // Вычисляем количество измерений для забывания
    int kMin = (int)MathCeil ((double)coords / 8.0 / (m + 1));
    int kMax = (int)MathCeil ((double)coords / 3.0 / (m + 1));
    int k    = u.RNDintInRange (kMin, kMax);

    // Обрабатываем агентов в группе
    int startIdx = GetGroupStartIndex (m);
    int endIdx   = GetGroupEndIndex   (m);

    for (int j = startIdx; j <= endIdx; j++)
    {
      // Memory strategy - сброс к лучшему решению группы
      ArrayCopy (a [j].c, groupBest [m].c, 0, 0, WHOLE_ARRAY);

      // Выбираем случайные измерения для забывания
      int dims [];
      ArrayResize (dims, coords);
      for (int i = 0; i < coords; i++) dims [i] = i;

      // Перемешиваем массив измерений
      for (int i = coords - 1; i > 0; i--)
      {
        int idx    = u.RNDintInRange (0, i);
        int temp   = dims [i];
        dims [i]   = dims [idx];
        dims [idx] = temp;
      }

      // Стратегия забывания и восполнения
      if (u.RNDprobab () < forgettingProb)
      {
        // Основная стратегия с косинусоидальной модуляцией
        for (int h = 0; h < k; h++)
        {
          int    dim              = dims [h];
          double range            = rangeMax [dim] - rangeMin [dim];
          double randomValue      = u.RNDprobab () * range + rangeMin [dim];
          double cosineModulation = (MathCos ((1.0 * currentIteration + totalIterations / 10.0) * M_PI / totalIterations) + 1.0) / 2.0;

          a [j].c [dim] = a [j].c [dim] + randomValue * cosineModulation;
          a [j].c [dim] = u.SeInDiSp (a [j].c [dim], rangeMin [dim], rangeMax [dim], rangeStep [dim]);
        }
      }
      else
      {
        // Dream sharing - копирование из случайного агента
        for (int h = 0; h < k; h++)
        {
          int dim   = dims [h];
          int donor = u.RNDintInRange (0, popSize - 1);
          a [j].c [dim] = a [donor].c [dim];
        }
      }
    }
  }
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Фаза эксплуатации (Exploitation phase)
void C_AO_DOA_dream::ExploitationPhase ()
{
  // В фазе эксплуатации все агенты движутся к глобальному лучшему
  for (int j = 0; j < popSize; j++)
  {
    // Сброс к глобальному лучшему решению
    ArrayCopy (a [j].c, cB, 0, 0, WHOLE_ARRAY);

    // Вычисляем количество измерений для модификации
    int km = MathMax (2, (int)MathCeil ((double)coords / 3.0));
    int k = u.RNDintInRange (2, km);

    // Выбираем случайные измерения
    int dims [];
    ArrayResize (dims, coords);
    for (int i = 0; i < coords; i++) dims [i] = i;

    // Перемешиваем массив измерений
    for (int i = coords - 1; i > 0; i--)
    {
      int idx = u.RNDintInRange (0, i);
      int temp = dims [i];
      dims [i] = dims [idx];
      dims [idx] = temp;
    }

    // Применяем стратегию забывания и дополнения
    for (int h = 0; h < k; h++)
    {
      int dim = dims [h];
      double range = rangeMax [dim] - rangeMin [dim];

      double randomValue = u.RNDprobab () * range + rangeMin [dim];
      double cosineModulation = (MathCos (currentIteration * M_PI / totalIterations) + 1.0) / 2.0;

      a [j].c [dim] = a [j].c [dim] + randomValue * cosineModulation;
      a [j].c [dim] = u.SeInDiSp (a [j].c [dim], rangeMin [dim], rangeMax [dim], rangeStep [dim]);
    }
  }
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Обновить лучшее решение в группе
void C_AO_DOA_dream::UpdateGroupBest (int groupNum)
{
  int startIdx = GetGroupStartIndex (groupNum);
  int endIdx   = GetGroupEndIndex (groupNum);

  for (int i = startIdx; i <= endIdx; i++)
  {
    if (a [i].f > groupBest [groupNum].f)
    {
      groupBest [groupNum].f = a [i].f;
      ArrayCopy (groupBest [groupNum].c, a [i].c, 0, 0, WHOLE_ARRAY);
    }
  }
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Получить начальный индекс группы
int C_AO_DOA_dream::GetGroupStartIndex (int groupNum)
{
  return (int)((double)groupNum * popSize / numGroups);
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Получить конечный индекс группы
int C_AO_DOA_dream::GetGroupEndIndex (int groupNum)
{
  int endIdx = (int)((double)(groupNum + 1) * popSize / numGroups) - 1;
  if (endIdx >= popSize) endIdx = popSize - 1;
  return endIdx;
}
//————————————————————————————————————————————————————————————————————

//————————————————————————————————————————————————————————————————————
//--- Обновление лучшего и худшего решений
void C_AO_DOA_dream::Revision ()
{
  // Обновляем глобальное лучшее решение
  for (int i = 0; i < popSize; i++)
  {
    if (a [i].f > fB)
    {
      fB = a [i].f;
      ArrayCopy (cB, a [i].c, 0, 0, WHOLE_ARRAY);
    }
  }

  // Обновляем лучшие решения групп в фазе исследования
  if (currentIteration <= explorationIters)
  {
    for (int m = 0; m < numGroups; m++)
    {
      if (groupBest [m].f > fB)
      {
        fB = groupBest [m].f;
        ArrayCopy (cB, groupBest [m].c, 0, 0, WHOLE_ARRAY);
      }
    }
  }
}
//————————————————————————————————————————————————————————————————————